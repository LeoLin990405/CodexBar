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
                sessionLabel: "5h Rate",
                weeklyLabel: "Weekly",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "Show StepFun usage",
                cliName: "stepfun",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: ProviderBrowserCookieDefaults.defaultImportOrder,
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
                sourceModes: [.auto, .api, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [StepFunWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "stepfun",
                aliases: ["step", "stepfun-ai"],
                versionDetector: nil))
    }
}

struct StepFunWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.web"
    let kind: ProviderFetchKind = .web
    private static let log = CodexBarLog.logger(LogCategories.stepfunUsage)

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        // API key is always required for balance
        guard Self.resolveAPIKey(environment: context.env) != nil else {
            return false
        }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveAPIKey(environment: context.env) else {
            throw StepFunUsageError.missingCredentials
        }

        // Try WKWebView dashboard scraping for plan/rate limit data (like AigoCode)
        var dashboardSnapshot: StepFunDashboardFetcher.DashboardSnapshot?
        #if os(macOS)
        if context.settings?.stepfun?.cookieSource != .off {
            do {
                let fetcher = StepFunDashboardFetcher()
                dashboardSnapshot = try await fetcher.fetchDashboard(timeout: 20)
                Self.log.debug("Got StepFun plan data from WKWebView dashboard")
            } catch {
                Self.log.debug("StepFun dashboard fetch failed: \(error.localizedDescription)")
            }
        }
        #endif

        var dashData: StepFunUsageFetcher.DashboardData?
        if let ds = dashboardSnapshot {
            dashData = StepFunUsageFetcher.DashboardData(
                planName: ds.planName,
                planExpiry: ds.planExpiry,
                fiveHourLeftPercent: ds.fiveHourLeftPercent,
                fiveHourResetTime: ds.fiveHourResetTime,
                weeklyLeftPercent: ds.weeklyLeftPercent,
                weeklyResetTime: ds.weeklyResetTime)
        }

        let snapshot = try await StepFunUsageFetcher.fetchUsage(
            apiKey: apiKey, dashboardData: dashData)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: dashboardSnapshot != nil ? "web+api" : "api")
    }

    func shouldFallback(on error: Error, context _: ProviderFetchContext) -> Bool {
        if case StepFunUsageError.missingCredentials = error { return false }
        return true
    }

    private static func resolveAPIKey(environment: [String: String]) -> String? {
        ProviderTokenResolver.stepfunToken(environment: environment)
    }
}
