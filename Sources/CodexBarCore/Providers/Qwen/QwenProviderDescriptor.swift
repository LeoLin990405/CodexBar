import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum QwenProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .qwen,
            metadata: ProviderMetadata(
                id: .qwen,
                displayName: "Qwen",
                sessionLabel: "请求",
                weeklyLabel: "每月",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 Qwen 用量",
                cliName: "qwen",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://bailian.console.aliyun.com/",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .qwen,
                iconResourceName: "ProviderIcon-qwen",
                color: ProviderColor(red: 106 / 255, green: 58 / 255, blue: 255 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Qwen 费用摘要暂不可用。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [QwenAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "qwen",
                aliases: ["tongyi", "dashscope", "lingma"],
                versionDetector: nil))
    }
}

struct QwenAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "qwen.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw QwenUsageError.missingCredentials
        }
        let usage = try await QwenUsageFetcher.fetchUsage(apiKey: apiKey)
        let accumulated = await LocalUsageTracker.shared.record(
            provider: .qwen,
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
        ProviderTokenResolver.qwenToken(environment: environment)
    }
}
