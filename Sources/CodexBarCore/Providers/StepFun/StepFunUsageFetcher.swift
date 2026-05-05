import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StepFunUsageSnapshot: Sendable {
    // API balance (prepaid account)
    public let balance: Double
    public let cashBalance: Double
    public let voucherBalance: Double
    public let accountType: String

    // Step Plan (coding subscription)
    public let planName: String?
    public let planExpiredAt: Date?
    public let planAutoRenew: Bool
    public let fiveHourLeftRate: Double?
    public let fiveHourResetTime: Date?
    public let weeklyLeftRate: Double?
    public let weeklyResetTime: Date?

    public let updatedAt: Date
    public let apiKeyValid: Bool

    public init(
        balance: Double,
        cashBalance: Double,
        voucherBalance: Double,
        accountType: String,
        planName: String? = nil,
        planExpiredAt: Date? = nil,
        planAutoRenew: Bool = false,
        fiveHourLeftRate: Double? = nil,
        fiveHourResetTime: Date? = nil,
        weeklyLeftRate: Double? = nil,
        weeklyResetTime: Date? = nil,
        updatedAt: Date,
        apiKeyValid: Bool = true)
    {
        self.balance = balance
        self.cashBalance = cashBalance
        self.voucherBalance = voucherBalance
        self.accountType = accountType
        self.planName = planName
        self.planExpiredAt = planExpiredAt
        self.planAutoRenew = planAutoRenew
        self.fiveHourLeftRate = fiveHourLeftRate
        self.fiveHourResetTime = fiveHourResetTime
        self.weeklyLeftRate = weeklyLeftRate
        self.weeklyResetTime = weeklyResetTime
        self.updatedAt = updatedAt
        self.apiKeyValid = apiKeyValid
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        // Primary: 5-hour rate limit if available, otherwise balance
        let primary: RateWindow
        if let rate = self.fiveHourLeftRate {
            let usedPercent = max(0, min(100, (1.0 - rate) * 100))
            let pctStr = String(format: "%.0f%%", rate * 100)
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 5 * 60,
                resetsAt: self.fiveHourResetTime,
                resetDescription: "5h remaining: \(pctStr)")
        } else {
            // Balance display: show as "active" with balance info, low usedPercent
            let balanceStr = String(format: "¥%.2f", self.balance)
            let voucherStr = self.voucherBalance > 0
                ? String(format: " (voucher: ¥%.2f)", self.voucherBalance) : ""
            primary = RateWindow(
                usedPercent: self.balance > 0 ? 0 : 100,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Balance: \(balanceStr)\(voucherStr)")
        }

        // Secondary: weekly rate limit if available, otherwise nil
        var secondary: RateWindow?
        if let weekRate = self.weeklyLeftRate {
            let weekUsed = max(0, min(100, (1.0 - weekRate) * 100))
            let weekPctStr = String(format: "%.0f%%", weekRate * 100)
            secondary = RateWindow(
                usedPercent: weekUsed,
                windowMinutes: 7 * 24 * 60,
                resetsAt: self.weeklyResetTime,
                resetDescription: "Weekly remaining: \(weekPctStr)")
        }

        // Tertiary: plan info + balance
        var tertiary: RateWindow?
        if let planName = self.planName {
            var desc = "\(planName) Plan"
            if let exp = self.planExpiredAt {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                desc += " → \(formatter.string(from: exp))"
            }
            let balanceStr = String(format: "¥%.2f", self.balance)
            desc += " | Balance: \(balanceStr)"
            tertiary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: self.planExpiredAt,
                resetDescription: desc)
        }

        let org: String? = if let planName = self.planName {
            "\(planName) Plan"
        } else {
            self.accountType == "prepaid" ? "Prepaid" : "Postpaid"
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .stepfun,
            accountEmail: nil,
            accountOrganization: org,
            loginMethod: nil)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}

public enum StepFunUsageError: LocalizedError, Sendable {
    case missingCredentials
    case networkError(String)
    case apiError(Int, String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "缺少 StepFun API key（STEPFUN_API_KEY）。"
        case let .networkError(message):
            "StepFun 网络错误：\(message)"
        case let .apiError(code, message):
            "StepFun API 错误（\(code)）：\(message)"
        case let .parseFailed(message):
            "解析 StepFun 响应失败：\(message)"
        }
    }
}

public struct StepFunUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.stepfunUsage)
    private static let accountsURL = URL(string: "https://api.stepfun.com/v1/accounts")!

    public static func fetchUsage(
        apiKey: String,
        dashboardData: DashboardData? = nil) async throws -> StepFunUsageSnapshot
    {
        try await self._fetchUsage(apiKey: apiKey, dashboardSnapshot: dashboardData)
    }

    public struct DashboardData: Sendable {
        public let planName: String?
        public let planExpiry: String?
        public let fiveHourLeftPercent: Double?
        public let fiveHourResetTime: String?
        public let weeklyLeftPercent: Double?
        public let weeklyResetTime: String?
    }

    private static func _fetchUsage(
        apiKey: String,
        dashboardSnapshot: DashboardData?) async throws -> StepFunUsageSnapshot
    {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StepFunUsageError.missingCredentials
        }

        // 1. Fetch API balance (always works with API key)
        let (balance, cashBalance, voucherBalance, accountType) = try await self.fetchAccountBalance(apiKey: apiKey)

        // 2. Map dashboard snapshot to our model
        var planName: String?
        var planExpiredAt: Date?
        let planAutoRenew = false
        var fiveHourLeftRate: Double?
        var fiveHourResetTime: Date?
        var weeklyLeftRate: Double?
        var weeklyResetTime: Date?

        if let dash = dashboardSnapshot {
            planName = dash.planName
            if let expStr = dash.planExpiry {
                // Parse "2026年04月22日"
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy年MM月dd日"
                planExpiredAt = fmt.date(from: expStr)
            }
            if let pct = dash.fiveHourLeftPercent {
                fiveHourLeftRate = pct / 100.0
            }
            if let pct = dash.weeklyLeftPercent {
                weeklyLeftRate = pct / 100.0
            }
            if let resetStr = dash.fiveHourResetTime {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                fiveHourResetTime = fmt.date(from: resetStr)
            }
            if let resetStr = dash.weeklyResetTime {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
                weeklyResetTime = fmt.date(from: resetStr)
            }
        }

        Self.log.debug(
            "StepFun balance=\(balance) plan=\(planName ?? "none") 5h=\(fiveHourLeftRate ?? -1) weekly=\(weeklyLeftRate ?? -1)") // swiftlint:disable:this line_length

        return StepFunUsageSnapshot(
            balance: balance,
            cashBalance: cashBalance,
            voucherBalance: voucherBalance,
            accountType: accountType,
            planName: planName,
            planExpiredAt: planExpiredAt,
            planAutoRenew: planAutoRenew,
            fiveHourLeftRate: fiveHourLeftRate,
            fiveHourResetTime: fiveHourResetTime,
            weeklyLeftRate: weeklyLeftRate,
            weeklyResetTime: weeklyResetTime,
            updatedAt: Date())
    }

    // MARK: - API Balance

    private static func fetchAccountBalance(apiKey: String) async throws -> (Double, Double, Double, String) {
        var request = URLRequest(url: self.accountsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StepFunUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let summary = Self.errorSummary(data: data)
            Self.log.error("StepFun accounts API returned \(httpResponse.statusCode): \(summary)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw StepFunUsageError.apiError(httpResponse.statusCode, "Invalid API key")
            }
            throw StepFunUsageError.apiError(httpResponse.statusCode, summary)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StepFunUsageError.parseFailed("Invalid JSON response")
        }

        let balance = (json["balance"] as? Double) ?? 0
        let cashBalance = (json["total_cash_balance"] as? Double) ?? 0
        let voucherBalance = (json["total_voucher_balance"] as? Double) ?? 0
        let accountType = (json["type"] as? String) ?? "prepaid"

        return (balance, cashBalance, voucherBalance, accountType)
    }

    // MARK: - Helpers

    private static func errorSummary(data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
