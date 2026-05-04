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
                sessionLabel: "Usage",
                weeklyLabel: "Quota",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show Trae usage",
                cliName: "trae",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://www.trae.ai/account-setting#usage",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .trae,
                iconResourceName: "ProviderIcon-trae",
                color: ProviderColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "Trae cost summary is not available." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in
                    [TraeWebFetchStrategy(), TraeLocalFetchStrategy()]
                })),
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

#if os(macOS)
struct TraeWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "trae.web"
    let kind: ProviderFetchKind = .web
    let backgroundPolicy: ProviderFetchBackgroundPolicy = .userInitiatedOnly
    private static let log = CodexBarLog.logger(LogCategories.traeWeb)

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        if context.sourceMode == .web { return true }
        if context.sourceMode == .auto {
            return TraeCookieImporter.hasSession()
        }
        return false
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieSession = try TraeCookieImporter.importSession()
        Self.log.debug("Found Trae session in \(cookieSession.sourceLabel)")

        let session = TraeSessionInfo(from: cookieSession)
        let snapshot = try await TraeUsageFetcher.fetchUsage(session: session)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "web (\(cookieSession.sourceLabel))")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        if context.sourceMode == .web { return false }
        // In auto mode, fall back to local probe on cookie/API errors
        return true
    }
}
#else
struct TraeWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "trae.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        false
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        throw TraeAPIError.networkError("Web strategy not available on this platform")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        true
    }
}
#endif
