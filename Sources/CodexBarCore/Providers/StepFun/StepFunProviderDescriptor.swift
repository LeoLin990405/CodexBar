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
                weeklyLabel: "每周",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示 StepFun 用量",
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
                noDataMessage: { "StepFun 费用摘要暂不可用。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .api, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    switch context.sourceMode {
                    case .web:
                        #if os(macOS)
                        return [StepFunWebDashboardFetchStrategy()]
                        #else
                        return []
                        #endif
                    case .api:
                        return [StepFunAPIFetchStrategy()]
                    case .auto:
                        #if os(macOS)
                        return [StepFunWebDashboardFetchStrategy(), StepFunAPIFetchStrategy()]
                        #else
                        return [StepFunAPIFetchStrategy()]
                        #endif
                    case .cli, .oauth:
                        return []
                    }
                })),
            cli: ProviderCLIConfig(
                name: "stepfun",
                aliases: ["step", "stepfun-ai"],
                versionDetector: nil))
    }
}

struct StepFunWebDashboardFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.webDashboard"
    let kind: ProviderFetchKind = .webDashboard
    let backgroundPolicy: ProviderFetchBackgroundPolicy = .userInitiatedOnly
    private static let log = CodexBarLog.logger(LogCategories.stepfunUsage)

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.sourceMode == .auto || context.sourceMode.usesWeb else {
            return false
        }
        guard context.settings?.stepfun?.cookieSource != .off else {
            return false
        }
        guard Self.resolveAPIKey(environment: context.env) != nil else {
            return false
        }
        return true
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveAPIKey(environment: context.env) else {
            throw StepFunUsageError.missingCredentials
        }

        #if os(macOS)
        let dashboardSnapshot = try await StepFunDashboardFetcher.fetchFromMainActor(timeout: 20)
        Self.log.debug("Got StepFun plan data from WKWebView dashboard")
        let dashData = StepFunUsageFetcher.DashboardData(
            planName: dashboardSnapshot.planName,
            planExpiry: dashboardSnapshot.planExpiry,
            fiveHourLeftPercent: dashboardSnapshot.fiveHourLeftPercent,
            fiveHourResetTime: dashboardSnapshot.fiveHourResetTime,
            weeklyLeftPercent: dashboardSnapshot.weeklyLeftPercent,
            weeklyResetTime: dashboardSnapshot.weeklyResetTime)

        let snapshot = try await StepFunUsageFetcher.fetchUsage(
            apiKey: apiKey, dashboardData: dashData)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "web+api")
        #else
        throw StepFunUsageError.missingCredentials
        #endif
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        if case StepFunUsageError.missingCredentials = error { return false }
        return context.sourceMode == .auto
    }

    private static func resolveAPIKey(environment: [String: String]) -> String? {
        ProviderTokenResolver.stepfunToken(environment: environment)
    }
}

struct StepFunAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.resolveAPIKey(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = Self.resolveAPIKey(environment: context.env) else {
            throw StepFunUsageError.missingCredentials
        }
        let snapshot = try await StepFunUsageFetcher.fetchUsage(
            apiKey: apiKey,
            dashboardData: nil)
        return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveAPIKey(environment: [String: String]) -> String? {
        ProviderTokenResolver.stepfunToken(environment: environment)
    }
}
