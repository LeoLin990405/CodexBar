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
                sessionLabel: "5h Window",
                weeklyLabel: "Weekly Window",
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
                statusPageURL: nil,
                statusLinkURL: nil),
            branding: ProviderBranding(
                iconStyle: .stepfun,
                iconResourceName: "ProviderIcon-stepfun",
                color: ProviderColor(red: 0.13, green: 0.59, blue: 0.95)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "StepFun per-day cost history is not available via API." }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: { context in
                    var strategies: [any ProviderFetchStrategy] = []
                    #if os(macOS)
                    if context.sourceMode.usesWeb {
                        strategies.append(StepFunWebDashboardFetchStrategy())
                    }
                    #endif
                    if context.sourceMode == .auto || context.sourceMode == .api {
                        strategies.append(StepFunAPIFetchStrategy())
                    }
                    return strategies
                })),
            cli: ProviderCLIConfig(
                name: "stepfun",
                aliases: ["step-fun", "sf"],
                versionDetector: nil))
    }
}

#if os(macOS)
struct StepFunWebDashboardFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.webDashboard"
    let kind: ProviderFetchKind = .webDashboard
    let backgroundPolicy: ProviderFetchBackgroundPolicy = .userInitiatedOnly

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        context.sourceMode.usesWeb && context.settings?.stepfun?.cookieSource != .off
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let snapshot = try await StepFunDashboardFetcher.fetchFromMainActor(timeout: context.webTimeout)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "webDashboard")
    }

    func shouldFallback(on _: Error, context: ProviderFetchContext) -> Bool {
        context.sourceMode == .auto
    }
}
#endif

struct StepFunAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        Self.hasCredentials(context: context)
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let token = try await Self.resolveToken(context: context)
        let usage = try await StepFunUsageFetcher.fetchUsage(token: token)
        return self.makeResult(
            usage: usage.toUsageSnapshot(),
            sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    // MARK: - Token Resolution

    private static func hasCredentials(context: ProviderFetchContext) -> Bool {
        let settings = context.settings?.stepfun
        if let settings {
            if !settings.manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            if !settings.username.isEmpty, !settings.password.isEmpty {
                return true
            }
        }
        if StepFunSettingsReader.token(environment: context.env) != nil {
            return true
        }
        if StepFunSettingsReader.username(environment: context.env) != nil,
           StepFunSettingsReader.password(environment: context.env) != nil
        {
            return true
        }
        return false
    }

    private static func resolveToken(context: ProviderFetchContext) async throws -> String {
        let settings = context.settings?.stepfun

        // 1. Manual settings token
        if let settings {
            let manualToken = settings.manualToken
            if !manualToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return StepFunTokenNormalizer.normalize(manualToken)
            }

            // 2. Username + password from Settings UI
            if !settings.username.isEmpty, !settings.password.isEmpty {
                return try await StepFunUsageFetcher.login(
                    username: settings.username,
                    password: settings.password)
            }
        }

        // 3. Direct token from env var
        if let token = StepFunSettingsReader.token(environment: context.env) {
            return token
        }

        // 4. Username + password from env vars
        if let username = StepFunSettingsReader.username(environment: context.env),
           let password = StepFunSettingsReader.password(environment: context.env)
        {
            return try await StepFunUsageFetcher.login(username: username, password: password)
        }

        throw StepFunUsageError.missingCredentials
    }
}

// MARK: - Token Normalizer

public enum StepFunTokenNormalizer {
    /// Normalize a StepFun TokenPlan credential. Cookie headers still contain the internal
    /// Oasis-Token field, but the user-facing feature is Step Plan / TokenPlan usage.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // If it looks like a cookie header, extract Oasis-Token
        if trimmed.contains("Oasis-Token=") {
            let parts = trimmed.components(separatedBy: "Oasis-Token=")
            if parts.count > 1 {
                let afterToken = parts[1]
                return afterToken.components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespaces) ?? afterToken
            }
        }

        return trimmed
    }
}
