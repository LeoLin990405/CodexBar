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
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [DoubaoAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "doubao",
                aliases: ["volcengine", "ark", "bytedance"],
                versionDetector: nil))
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

        // Try Volcengine console GetCodingPlanUsage first — it carries real
        // session/weekly/monthly quotas. Fall back to chat-completion probe
        // when cookies are missing / expired.
        #if os(macOS)
        do {
            let consoleResult = try await DoubaoConsoleFetcher.fetch(
                browserDetection: BrowserDetection(cacheTTL: 0))
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
        } catch {
            Self.consoleLog.debug("Doubao console fetch failed, falling back: \(error)")
        }
        #endif

        let usage = try await DoubaoUsageFetcher.fetchUsage(apiKey: apiKey)
        let accumulated = await LocalUsageTracker.shared.record(
            provider: .doubao,
            remaining: usage.remainingRequests,
            limit: usage.limitRequests)
        return self.makeResult(
            usage: usage.toUsageSnapshot(accumulated: accumulated),
            sourceLabel: "api")
    }

    #if os(macOS)
    private static let consoleLog = CodexBarLog.logger(LogCategories.doubaoUsage)
    #endif

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.doubaoToken(environment: environment)
    }
}
