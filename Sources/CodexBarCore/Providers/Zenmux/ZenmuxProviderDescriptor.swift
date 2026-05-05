import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum ZenmuxProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .zenmux,
            metadata: ProviderMetadata(
                id: .zenmux,
                displayName: "Zenmux",
                sessionLabel: "请求",
                weeklyLabel: "速率限制",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 Zenmux 用量",
                cliName: "zenmux",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://zenmux.ai/platform/subscription",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .zenmux,
                iconResourceName: "ProviderIcon-zenmux",
                color: ProviderColor(red: 255 / 255, green: 140 / 255, blue: 0 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Zenmux 费用摘要暂不可用。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [ZenmuxAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "zenmux",
                aliases: ["zen"],
                versionDetector: nil))
    }
}

struct ZenmuxAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "zenmux.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw ZenmuxUsageError.missingCredentials
        }
        let usage = try await ZenmuxUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.zenmuxToken(environment: environment)
    }
}
