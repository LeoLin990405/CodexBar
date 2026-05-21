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
                dashboardURL: "https://platform.stepfun.com/plan-usage",
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
                sourceModes: [.auto, .web],
                pipeline: ProviderFetchPipeline(resolveStrategies: { _ in [StepFunWebFetchStrategy()] })),
            cli: ProviderCLIConfig(
                name: "stepfun",
                aliases: ["step-fun", "sf"],
                versionDetector: nil))
    }
}

struct StepFunWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "stepfun.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.settings?.stepfun?.cookieSource != .off else { return false }

        if context.settings?.stepfun?.cookieSource == .manual {
            return !(context.settings?.stepfun?.manualToken.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
        }
        if CookieHeaderCache.load(provider: .stepfun) != nil { return true }
        if StepFunSettingsReader.token(environment: context.env) != nil { return true }
        if StepFunSettingsReader.username(environment: context.env) != nil,
           StepFunSettingsReader.password(environment: context.env) != nil
        {
            return true
        }
        #if os(macOS)
        if StepFunCookieImporter.hasSession(browserDetection: context.browserDetection) { return true }
        #endif
        return false
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieSource = context.settings?.stepfun?.cookieSource ?? .auto

        do {
            let auth = try await Self.resolveAuthContext(context: context, allowCached: true)
            let usage = try await StepFunUsageFetcher.fetchUsage(auth: auth)
            return self.makeResult(
                usage: usage.toUsageSnapshot(),
                sourceLabel: "web")
        } catch StepFunUsageError.apiError where cookieSource != .manual {
            // Token may be stale — clear cache and retry with fresh login
            CookieHeaderCache.clear(provider: .stepfun)
            let auth = try await Self.resolveAuthContext(context: context, allowCached: false)
            let usage = try await StepFunUsageFetcher.fetchUsage(auth: auth)
            return self.makeResult(
                usage: usage.toUsageSnapshot(),
                sourceLabel: "web")
        }
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    // MARK: - Token Resolution

    private static func resolveAuthContext(
        context: ProviderFetchContext,
        allowCached: Bool) async throws -> StepFunAuthContext
    {
        let settings = context.settings?.stepfun

        // 1. Manual mode: use the token directly from settings
        if settings?.cookieSource == .manual {
            let manualToken = settings?.manualToken ?? ""
            let auth = StepFunTokenNormalizer.authContext(from: manualToken)
            guard !auth.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StepFunUsageError.missingToken
            }
            return auth
        }

        // 2. Cached token from previous login
        if allowCached, let cached = CookieHeaderCache.load(provider: .stepfun) {
            return StepFunTokenNormalizer.authContext(from: cached.cookieHeader)
        }

        // 3. Browser cookie import: reuse an existing platform.stepfun.com login.
        #if os(macOS)
        if let auth = Self.resolveBrowserAuthContext(context: context) {
            return auth
        }
        #endif

        // 4. Username + password from Settings UI → perform full login flow
        //    (register device → sign in by password → get Oasis-Token)
        if let settings, !settings.username.isEmpty, !settings.password.isEmpty {
            let token = try await StepFunUsageFetcher.login(
                username: settings.username,
                password: settings.password)
            let auth = StepFunAuthContext(token: token, webID: StepFunUsageFetcher.defaultWebID)
            CookieHeaderCache.store(
                provider: .stepfun,
                cookieHeader: StepFunTokenNormalizer.cookieHeader(token: auth.token, webID: auth.webID),
                sourceLabel: "login")
            return auth
        }

        // 5. Direct token from env var
        if let token = StepFunSettingsReader.token(environment: context.env) {
            return StepFunAuthContext(
                token: StepFunTokenNormalizer.normalize(token),
                webID: StepFunSettingsReader.webID(environment: context.env)
                    ?? StepFunTokenNormalizer.webID(from: token))
        }

        // 6. Username + password from env vars → perform full login flow
        if let username = StepFunSettingsReader.username(environment: context.env),
           let password = StepFunSettingsReader.password(environment: context.env)
        {
            let token = try await StepFunUsageFetcher.login(username: username, password: password)
            let auth = StepFunAuthContext(token: token, webID: StepFunUsageFetcher.defaultWebID)
            CookieHeaderCache.store(
                provider: .stepfun,
                cookieHeader: StepFunTokenNormalizer.cookieHeader(token: auth.token, webID: auth.webID),
                sourceLabel: "login")
            return auth
        }

        throw StepFunUsageError.missingCredentials
    }

    #if os(macOS)
    private static func resolveBrowserAuthContext(context: ProviderFetchContext) -> StepFunAuthContext? {
        do {
            let session = try StepFunCookieImporter.importSession(browserDetection: context.browserDetection)
            guard let auth = session.authContext,
                  !auth.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let cookieHeader = session.cookieHeader
            else {
                return nil
            }
            CookieHeaderCache.store(provider: .stepfun, cookieHeader: cookieHeader, sourceLabel: session.sourceLabel)
            return auth
        } catch {
            return nil
        }
    }
    #endif
}

// MARK: - Token Normalizer

public enum StepFunTokenNormalizer {
    /// Normalize a StepFun token value — extracts the Oasis-Token from a cookie header
    /// or returns the raw token value if it's not a cookie header.
    public static func normalize(_ raw: String) -> String {
        self.authContext(from: raw).token
    }

    public static func webID(from raw: String) -> String? {
        self.cookieValue(named: "Oasis-Webid", in: raw)
    }

    public static func authContext(from raw: String, fallbackWebID: String? = nil) -> StepFunAuthContext {
        let trimmed = self.normalizedCookieInput(raw)
        guard !trimmed.isEmpty else {
            return StepFunAuthContext(token: "", webID: fallbackWebID)
        }

        let token = self.cookieValue(named: "Oasis-Token", in: trimmed) ?? trimmed
        return StepFunAuthContext(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            webID: self.webID(from: trimmed) ?? fallbackWebID)
    }

    public static func cookieHeader(token: String, webID: String?) -> String {
        let normalizedToken = self.normalize(token)
        let normalizedWebID = webID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalizedWebID.isEmpty else {
            return normalizedToken
        }
        return "Oasis-Token=\(normalizedToken); Oasis-Webid=\(normalizedWebID)"
    }

    private static func cookieValue(named name: String, in raw: String) -> String? {
        let trimmed = self.normalizedCookieInput(raw)
        guard !trimmed.isEmpty else { return nil }

        for part in trimmed.components(separatedBy: ";") {
            let pair = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pair.hasPrefix("\(name)=") else { continue }
            let value = pair.dropFirst(name.count + 1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func normalizedCookieInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("cookie:") else { return trimmed }
        return trimmed.dropFirst("cookie:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
