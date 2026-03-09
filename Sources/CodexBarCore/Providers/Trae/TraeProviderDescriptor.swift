import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum TraeProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .trae,
            metadata: ProviderMetadata(
                id: .trae,
                displayName: "Trae",
                sessionLabel: "Status",
                weeklyLabel: "Usage",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Trae status",
                cliName: "trae",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://www.trae.ai",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .trae,
                iconResourceName: "ProviderIcon-trae",
                color: ProviderColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Trae cost summary is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [TraeLocalFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "trae",
                aliases: [],
                versionDetector: nil))
    }
}

struct TraeLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "trae.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/Trae.app")
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let status = try await TraeStatusProbe.probe()
        return self.makeResult(
            usage: status.toUsageSnapshot(),
            sourceLabel: "local")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
