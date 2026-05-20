import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum VeniceProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .venice,
            metadata: ProviderMetadata(
                id: .venice,
                displayName: "Venice",
                sessionLabel: "余额",
                weeklyLabel: "余额",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 Venice 使用量",
                cliName: "venice",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://venice.ai/settings/api",
                statusPageURL: nil,
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .venice,
                iconResourceName: "ProviderIcon-venice",
                color: ProviderColor(red: 0.2, green: 0.6, blue: 1.0)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Venice 按天费用历史暂不可用（API 不返回）。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [VeniceAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "venice",
                aliases: ["ven"],
                versionDetector: nil))
    }
}

struct VeniceAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "venice.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw VeniceUsageError.missingCredentials
        }
        let usage = try await VeniceUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.veniceToken(environment: environment)
    }
}
