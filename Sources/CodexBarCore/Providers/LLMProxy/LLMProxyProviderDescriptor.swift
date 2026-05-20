import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum LLMProxyProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .llmproxy,
            metadata: ProviderMetadata(
                id: .llmproxy,
                displayName: "LLM 代理",
                sessionLabel: "配额",
                weeklyLabel: "请求次数",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 LLM 代理使用量",
                cliName: "llmproxy",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .llmproxy,
                iconResourceName: "ProviderIcon-llmproxy",
                color: ProviderColor(red: 36 / 255, green: 180 / 255, blue: 126 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "LLM 代理费用历史已在配额统计摘要中提供。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [LLMProxyAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "llmproxy",
                aliases: ["llm-api-key-proxy", "llm-proxy"],
                versionDetector: nil))
    }
}

struct LLMProxyAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "llmproxy.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.llmProxyToken(environment: context.env) != nil &&
            LLMProxySettingsReader.baseURL(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.llmProxyToken(environment: context.env) else {
            throw LLMProxyUsageError.missingCredentials
        }
        guard let baseURL = LLMProxySettingsReader.baseURL(environment: context.env) else {
            throw LLMProxyUsageError.missingBaseURL
        }
        let usage = try await LLMProxyUsageFetcher.fetchUsage(apiKey: apiKey, baseURL: baseURL)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
