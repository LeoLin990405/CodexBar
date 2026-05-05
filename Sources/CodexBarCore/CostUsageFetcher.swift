import Foundation

public enum CostUsageError: LocalizedError, Sendable {
    case unsupportedProvider(UsageProvider)
    case timedOut(seconds: Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedProvider(provider):
            return "\(provider.rawValue) 暂不支持费用摘要。"
        case let .timedOut(seconds):
            if seconds >= 60, seconds % 60 == 0 {
                return "费用刷新在 \(seconds / 60) 分钟后超时。"
            }
            return "费用刷新在 \(seconds) 秒后超时。"
        }
    }
}

public struct CostUsageFetcher: Sendable {
    public init() {}

    public func loadTokenSnapshot(
        provider: UsageProvider,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false) async throws -> CostUsageTokenSnapshot
    {
        try await Self.loadTokenSnapshot(
            provider: provider,
            now: now,
            forceRefresh: forceRefresh,
            allowVertexClaudeFallback: allowVertexClaudeFallback)
    }

    static func loadTokenSnapshot(
        provider: UsageProvider,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowVertexClaudeFallback: Bool = false,
        scannerOptions overrideScannerOptions: CostUsageScanner.Options? = nil,
        piScannerOptions overridePiScannerOptions: PiSessionCostScanner
            .Options? = nil) async throws -> CostUsageTokenSnapshot
    {
        guard provider == .codex || provider == .claude || provider == .vertexai else {
            throw CostUsageError.unsupportedProvider(provider)
        }

        let until = now
        // Rolling window: last 30 days (inclusive). Use -29 for inclusive boundaries.
        let since = Calendar.current.date(byAdding: .day, value: -29, to: now) ?? now

        var options = overrideScannerOptions ?? CostUsageScanner.Options()
        if provider == .vertexai {
            options.claudeLogProviderFilter = allowVertexClaudeFallback ? .all : .vertexAIOnly
        } else if provider == .claude {
            options.claudeLogProviderFilter = .excludeVertexAI
        }
        // Always set TTL to 0: the scanner-level TTL is redundant with per-file mtime/size
        // caching in processClaudeFile, and a non-zero TTL causes stale data after the first scan.
        options.refreshMinIntervalSeconds = 0
        if forceRefresh {
            options.forceRescan = true
        }
        var daily = CostUsageScanner.loadDailyReport(
            provider: provider,
            since: since,
            until: until,
            now: now,
            options: options)

        if provider == .vertexai,
           !allowVertexClaudeFallback,
           options.claudeLogProviderFilter == .vertexAIOnly,
           daily.data.isEmpty
        {
            var fallback = options
            fallback.claudeLogProviderFilter = .all
            daily = CostUsageScanner.loadDailyReport(
                provider: provider,
                since: since,
                until: until,
                now: now,
                options: fallback)
        }

        if provider == .codex || provider == .claude {
            var piOptions = overridePiScannerOptions ?? PiSessionCostScanner.Options()
            if piOptions.cacheRoot == nil {
                piOptions.cacheRoot = options.cacheRoot
            }
            if forceRefresh {
                piOptions.refreshMinIntervalSeconds = 0
                piOptions.forceRescan = true
            }
            let piReport = PiSessionCostScanner.loadDailyReport(
                provider: provider,
                since: since,
                until: until,
                now: now,
                options: piOptions)
            daily = CostUsageDailyReport.merged([daily, piReport])
        }

        return Self.tokenSnapshot(from: daily, now: now)
    }

    static func tokenSnapshot(from daily: CostUsageDailyReport, now: Date) -> CostUsageTokenSnapshot {
        // Pick the most recent day; break ties by cost/tokens to keep a stable "session" row.
        let currentDay = daily.data.max { lhs, rhs in
            let lDate = CostUsageDateParser.parse(lhs.date) ?? .distantPast
            let rDate = CostUsageDateParser.parse(rhs.date) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.date < rhs.date
        }
        // Prefer summary totals when present; fall back to summing daily entries.
        let totalFromSummary = daily.summary?.totalCostUSD
        let totalFromEntries = daily.data.compactMap(\.costUSD).reduce(0, +)
        let last30DaysCostUSD = totalFromSummary ?? (totalFromEntries > 0 ? totalFromEntries : nil)
        let totalTokensFromSummary = daily.summary?.totalTokens
        let totalTokensFromEntries = daily.data.compactMap(\.totalTokens).reduce(0, +)
        let last30DaysTokens = totalTokensFromSummary ?? (totalTokensFromEntries > 0 ? totalTokensFromEntries : nil)

        return CostUsageTokenSnapshot(
            sessionTokens: currentDay?.totalTokens,
            sessionCostUSD: currentDay?.costUSD,
            last30DaysTokens: last30DaysTokens,
            last30DaysCostUSD: last30DaysCostUSD,
            daily: daily.data,
            updatedAt: now)
    }

    static func selectCurrentSession(from sessions: [CostUsageSessionReport.Entry])
        -> CostUsageSessionReport.Entry?
    {
        if sessions.isEmpty { return nil }
        return sessions.max { lhs, rhs in
            let lDate = CostUsageDateParser.parse(lhs.lastActivity) ?? .distantPast
            let rDate = CostUsageDateParser.parse(rhs.lastActivity) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.session < rhs.session
        }
    }

    static func selectMostRecentMonth(from months: [CostUsageMonthlyReport.Entry])
        -> CostUsageMonthlyReport.Entry?
    {
        if months.isEmpty { return nil }
        return months.max { lhs, rhs in
            let lDate = CostUsageDateParser.parseMonth(lhs.month) ?? .distantPast
            let rDate = CostUsageDateParser.parseMonth(rhs.month) ?? .distantPast
            if lDate != rDate { return lDate < rDate }
            let lCost = lhs.costUSD ?? -1
            let rCost = rhs.costUSD ?? -1
            if lCost != rCost { return lCost < rCost }
            let lTokens = lhs.totalTokens ?? -1
            let rTokens = rhs.totalTokens ?? -1
            if lTokens != rTokens { return lTokens < rTokens }
            return lhs.month < rhs.month
        }
    }
}
