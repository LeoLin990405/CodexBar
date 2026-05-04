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
                sessionLabel: "Subscription",
                weeklyLabel: "Weekly",
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
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    var strategies: [any ProviderFetchStrategy] = []
                    let hasAPIToken = ProviderTokenResolver.aigocodeToken(environment: context.env) != nil
                    if ProviderInteractionContext.current == .background,
                       context.sourceMode == .auto,
                       hasAPIToken
                    {
                        return [AigoCodeAPIFetchStrategy()]
                    }
                    // Prefer web dashboard when available (works without API key).
                    #if os(macOS)
                    if context.sourceMode.usesWeb || context.sourceMode == .auto {
                        strategies.append(AigoCodeWebDashboardFetchStrategy())
                    }
                    #endif
                    strategies.append(AigoCodeAPIFetchStrategy())
                    return strategies
                })),
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

#if os(macOS)
/// Fetches AigoCode usage by rendering the dashboard in an offscreen WKWebView.
/// This works without an API key — the user just needs to be logged in via the WebKit session.
struct AigoCodeWebDashboardFetchStrategy: ProviderFetchStrategy {
    let id: String = "aigocode.webDashboard"
    let kind: ProviderFetchKind = .webDashboard
    private static let log = CodexBarLog.logger(LogCategories.aigocodeWeb)

    /// The web strategy is always considered available on macOS. If the user isn't logged in,
    /// `fetch` will throw `loginRequired` and the pipeline falls back to the API strategy.
    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode.usesWeb || context.sourceMode == .auto
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        // Try to import the Supabase session from Chrome's localStorage.
        // AigoCode uses Supabase Auth which stores JWT tokens in localStorage, not cookies.
        let session = AigoCodeLocalStorageImporter.importSession()
        if let session {
            Self.log.debug("Found Supabase session in \(session.sourceLabel)")
        } else {
            Self.log.debug("No Supabase session found in browser localStorage")
        }

        let snapshot = try await MainActor.run {
            AigoCodeDashboardFetcher()
        }.fetchDashboard(
            supabaseTokenJSON: session?.tokenJSON,
            timeout: context.webTimeout)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "webDashboard")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        // Fall back to API strategy if web fails (login required, timeout, etc.)
        if context.sourceMode == .auto { return true }
        if context.sourceMode == .web { return false }
        return true
    }
}
#endif
