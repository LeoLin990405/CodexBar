import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum StepFunProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .stepfun,
            metadata: ProviderMetadata(
                id: .stepfun,
                displayName: "StepFun",
                sessionLabel: "Balance",
                weeklyLabel: "Account",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show StepFun usage",
                cliName: "stepfun",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://platform.stepfun.com/plan-subscribe",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .stepfun,
                iconResourceName: "ProviderIcon-stepfun",
                color: ProviderColor(red: 99 / 255, green: 102 / 255, blue: 241 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "StepFun cost summary is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [StepFunAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "stepfun",
                aliases: ["step", "stepfun-ai"],
                versionDetector: nil))
    }
}

struct StepFunAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveToken(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveToken(environment: context.env) else {
            throw StepFunUsageError.missingCredentials
        }
        let usage = try await StepFunUsageFetcher.fetchUsage(apiKey: apiKey)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveToken(environment: [String: String]) -> String? {
        ProviderTokenResolver.stepfunToken(environment: environment)
    }
}
