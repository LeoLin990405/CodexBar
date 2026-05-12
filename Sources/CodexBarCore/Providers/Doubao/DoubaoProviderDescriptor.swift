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
                displayName: "豆包",
                sessionLabel: "请求",
                weeklyLabel: "速率限制",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示豆包用量",
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
                noDataMessage: { "豆包暂不支持费用摘要。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    var strategies: [any ProviderFetchStrategy] = []
                    #if os(macOS)
                    if context.sourceMode.usesWeb {
                        strategies.append(DoubaoConsoleFetchStrategy())
                    }
                    #endif
                    if context.sourceMode == .auto || context.sourceMode == .api {
                        strategies.append(DoubaoAPIFetchStrategy())
                    }
                    return strategies
                })),
            cli: ProviderCLIConfig(
                name: "doubao",
                aliases: ["volcengine", "ark", "bytedance"],
                versionDetector: nil))
    }
}

#if os(macOS)
struct DoubaoConsoleFetchStrategy: ProviderFetchStrategy {
    let id: String = "doubao.console"
    let kind: ProviderFetchKind = .webDashboard
    let backgroundPolicy: ProviderFetchBackgroundPolicy = .userInitiatedOnly

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode.usesWeb
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let result = try await DoubaoConsoleFetcher.fetch(browserDetection: context.browserDetection)
        return self.makeResult(
            usage: result.toUsageSnapshot(),
            sourceLabel: "console")
    }

    func shouldFallback(on _: Error, context: ProviderFetchContext) -> Bool {
        context.sourceMode == .auto
    }
}
#endif

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
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.doubaoToken(environment: environment)
    }
}
