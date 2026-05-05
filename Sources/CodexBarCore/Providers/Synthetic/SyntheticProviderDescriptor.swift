import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum SyntheticProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .synthetic,
            metadata: ProviderMetadata(
                id: .synthetic,
                displayName: "Synthetic",
                sessionLabel: "5 小时额度",
                weeklyLabel: "每周 token",
                opusLabel: "搜索小时额度",
                supportsOpus: true,
                supportsCredits: false,
                creditsHint: "Weekly token quota regenerates continuously.",
                toggleTitle: "显示 Synthetic 用量",
                cliName: "synthetic",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: nil,
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .synthetic,
                iconResourceName: "ProviderIcon-synthetic",
                color: ProviderColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Synthetic 暂不支持费用摘要。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [SyntheticAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "synthetic",
                aliases: ["synthetic.new"],
                versionDetector: nil))
    }
}

struct SyntheticAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "synthetic.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw SyntheticSettingsError.missingToken
        }
        let usage = try await SyntheticUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.syntheticToken(environment: environment)
    }
}
