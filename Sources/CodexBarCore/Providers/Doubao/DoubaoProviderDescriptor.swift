import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum DoubaoProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .doubao,
            metadata: ProviderMetadata(
                id: .doubao,
                displayName: "Doubao",
                sessionLabel: "5h",
                weeklyLabel: "Week",
                opusLabel: "Month",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Doubao usage",
                cliName: "doubao",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=subscribe",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .doubao,
                iconResourceName: "ProviderIcon-doubao",
                color: ProviderColor(red: 51 / 255, green: 112 / 255, blue: 255 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Doubao cost summary is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    switch context.sourceMode {
                    case .web:
                        #if os(macOS)
                        return [DoubaoConsoleFetchStrategy()]
                        #else
                        return []
                        #endif
                    case .api:
                        return [DoubaoAPIFetchStrategy()]
                    case .auto:
                        #if os(macOS)
                        return [DoubaoConsoleFetchStrategy(), DoubaoAPIFetchStrategy()]
                        #else
                        return [DoubaoAPIFetchStrategy()]
                        #endif
                    case .cli, .oauth:
                        return []
                    }
                })),
            cli: ProviderCLIConfig(
                name: "doubao",
                aliases: ["volcengine", "ark", "bytedance"],
                versionDetector: nil))
    }
}

struct DoubaoConsoleFetchStrategy: ProviderFetchStrategy {
    let id: String = "doubao.console"
    let kind: ProviderFetchKind = .webDashboard
    let backgroundPolicy: ProviderFetchBackgroundPolicy = .userInitiatedOnly
    private static let log = CodexBarLog.logger(LogCategories.doubaoUsage)

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode == .auto || context.sourceMode.usesWeb
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        #if os(macOS)
        let consoleResult = try await DoubaoConsoleFetcher.fetch(
            browserDetection: context.browserDetection)
        let snapshot = DoubaoUsageSnapshot(
            remainingRequests: 0,
            limitRequests: 0,
            resetTime: consoleResult.quotas.first?.resetAt,
            updatedAt: consoleResult.updatedAt,
            apiKeyValid: true,
            codingPlanQuotas: consoleResult.quotas)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "console")
        #else
        throw DoubaoUsageError.missingCredentials
        #endif
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        guard context.sourceMode == .auto else { return false }
        Self.log.debug("Doubao console fetch failed, falling back: \(error)")
        return true
    }
}

struct DoubaoAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "doubao.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw DoubaoUsageError.missingCredentials
        }

        let usage = try await DoubaoUsageFetcher.fetchUsage(apiKey: apiKey)
        let accumulated = await LocalUsageTracker.shared.record(
            provider: .doubao,
            remaining: usage.remainingRequests,
            limit: usage.limitRequests)
        return self.makeResult(
            usage: usage.toUsageSnapshot(accumulated: accumulated),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.doubaoToken(environment: environment)
    }
}
