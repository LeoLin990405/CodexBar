import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum VertexAIProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .vertexai,
            metadata: ProviderMetadata(
                id: .vertexai,
                displayName: "Vertex AI",
                sessionLabel: "请求",
                weeklyLabel: "Tokens",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 Vertex AI 用量",
                cliName: "vertexai",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                dashboardURL: "https://console.cloud.google.com/vertex-ai",
                statusPageURL: nil,
                statusLinkURL: "https://status.cloud.google.com"),
            branding: ProviderBranding(
                iconStyle: .vertexai,
                iconResourceName: "ProviderIcon-vertexai",
                color: ProviderColor(red: 66 / 255, green: 133 / 255, blue: 244 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: true,
                noDataMessage: { "Claude 日志中未找到 Vertex AI 费用数据。请确认条目包含 Vertex 元数据。"
                }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .oauth],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [VertexAIOAuthFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "vertexai",
                versionDetector: nil))
    }
}

struct VertexAIOAuthFetchStrategy: ProviderFetchStrategy {
    let id: String = "vertexai.oauth"
    let kind: ProviderFetchKind = .oauth

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        (try? VertexAIOAuthCredentialsStore.load()) != nil
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        var credentials = try VertexAIOAuthCredentialsStore.load()

        // Refresh token if expired
        if credentials.needsRefresh {
            credentials = try await VertexAITokenRefresher.refresh(credentials)
            try VertexAIOAuthCredentialsStore.save(credentials)
        }

        // Fetch quota usage from Cloud Monitoring. If no data is found (e.g., no recent
        // Vertex AI requests), return an empty snapshot so token costs can still display.
        let usage: VertexAIUsageResponse?
        do {
            usage = try await VertexAIUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                projectId: credentials.projectId)
        } catch VertexAIFetchError.noData {
            // No quota data is fine - token costs from local logs can still be shown.
            usage = nil
        }

        return self.makeResult(
            usage: Self.mapUsage(usage, credentials: credentials),
            sourceLabel: "oauth")
    }

    func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
        if error is VertexAIOAuthCredentialsError { return true }
        if let fetchError = error as? VertexAIFetchError {
            switch fetchError {
            case .unauthorized, .forbidden:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func mapUsage(
        _ response: VertexAIUsageResponse?,
        credentials: VertexAIOAuthCredentials) -> UsageSnapshot
    {
        // Token cost is fetched separately via CostUsageScanner from local Claude logs.
        // Quota usage from Cloud Monitoring is optional - we still show token costs if unavailable.

        let identity = ProviderIdentitySnapshot(
            providerID: .vertexai,
            accountEmail: credentials.email,
            accountOrganization: credentials.projectId,
            loginMethod: "gcloud")

        return UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: nil,
            updatedAt: Date(),
            identity: identity)
    }
}
