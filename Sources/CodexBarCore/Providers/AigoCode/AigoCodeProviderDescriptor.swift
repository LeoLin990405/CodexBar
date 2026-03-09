import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum AigoCodeProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .aigocode,
            metadata: ProviderMetadata(
                id: .aigocode,
                displayName: "AigoCode",
                sessionLabel: "Requests",
                weeklyLabel: "Rate limit",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show AigoCode usage",
                cliName: "aigocode",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://www.aigocode.com/dashboard/console",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .aigocode,
                iconResourceName: "ProviderIcon-aigocode",
                color: ProviderColor(red: 34 / 255, green: 197 / 255, blue: 94 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "AigoCode cost summary is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [AigoCodeAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "aigocode",
                aliases: ["aigo"],
                versionDetector: nil))
    }
}

struct AigoCodeAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "aigocode.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw AigoCodeUsageError.missingCredentials
        }
        let usage = try await AigoCodeUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.aigocodeToken(environment: environment)
    }
}
