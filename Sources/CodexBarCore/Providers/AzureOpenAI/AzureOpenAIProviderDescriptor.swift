import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum AzureOpenAIProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .azureopenai,
            metadata: ProviderMetadata(
                id: .azureopenai,
                displayName: "微软云 OpenAI",
                sessionLabel: "状态",
                weeklyLabel: "部署",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示微软云 OpenAI 状态",
                cliName: "azure-openai",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://ai.azure.com",
                statusPageURL: nil,
                statusLinkURL: "https://azure.status.microsoft/en-us/status"),
            branding: ProviderBranding(
                iconStyle: .openai,
                iconResourceName: "ProviderIcon-codex",
                color: ProviderColor(red: 0, green: 120 / 255, blue: 212 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "微软云 OpenAI 使用历史暂不可用。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [AzureOpenAIAPIFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "azure-openai",
                aliases: ["azureopenai", "aoai"],
                versionDetector: nil))
    }
}

struct AzureOpenAIAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "azureopenai.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        _ = context
        // Keep the strategy available so missing partial configuration surfaces
        // as a precise settings error instead of a generic no-strategy failure.
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveAPIKey(environment: context.env) else {
            throw AzureOpenAIUsageError.missingAPIKey
        }
        guard let endpoint = Self.resolveEndpoint(environment: context.env) else {
            throw AzureOpenAIUsageError.missingEndpoint
        }
        guard let deploymentName = Self.resolveDeploymentName(environment: context.env) else {
            throw AzureOpenAIUsageError.missingDeploymentName
        }

        let usage = try await AzureOpenAIUsageFetcher.fetchUsage(
            apiKey: apiKey,
            endpoint: endpoint,
            deploymentName: deploymentName,
            apiVersion: AzureOpenAISettingsReader.apiVersion(environment: context.env))
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "deployment")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveAPIKey(environment: [String: String]) -> String? {
        ProviderTokenResolver.azureOpenAIToken(environment: environment)
    }

    private static func resolveEndpoint(environment: [String: String]) -> URL? {
        AzureOpenAISettingsReader.endpoint(environment: environment)
    }

    private static func resolveDeploymentName(environment: [String: String]) -> String? {
        AzureOpenAISettingsReader.deploymentName(environment: environment)
    }
}
