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
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "trae",
                aliases: [],
                versionDetector: nil))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .web:
            [TraeWebFetchStrategy()]
        case .auto:
            [TraeCachedSessionFetchStrategy(), TraeWebFetchStrategy(), TraeLocalFetchStrategy()]
        case .api, .cli, .oauth:
            []
        }
    }
}

struct TraeLocalFetchStrategy: ProviderFetchStrategy {
    let id: String = "trae.local"
    let kind: ProviderFetchKind = .localProbe

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        TraeStatusProbe.isInstalled()
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let status = try await TraeStatusProbe.probe()
        return self.makeResult(
            usage: status.toUsageSnapshot(),
            sourceLabel: "local")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}

struct TraeCachedSessionFetchStrategy: ProviderFetchStrategy {
    let id: String = "trae.cached-session"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        #if os(macOS)
        guard let cached = CookieHeaderCache.load(provider: .trae) else { return false }
        return !cached.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #else
        false
        #endif
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        #if os(macOS)
        guard let cached = CookieHeaderCache.load(provider: .trae),
              !cached.cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw TraeAPIError.invalidSession
        }

        do {
            let session = TraeSessionInfo(
                cookieHeader: cached.cookieHeader,
                csrfToken: TraeCookieHeader.csrfToken(from: cached.cookieHeader),
                cloudideSession: TraeCookieHeader.cloudideSession(from: cached.cookieHeader),
                sourceLabel: cached.sourceLabel)
            let snapshot = try await TraeUsageFetcher.fetchUsage(session: session)
            return self.makeResult(
                usage: snapshot.toUsageSnapshot(),
                sourceLabel: "cached session")
        } catch TraeAPIError.invalidSession {
            CookieHeaderCache.clear(provider: .trae)
            throw TraeAPIError.invalidSession
        }
        #else
        throw TraeAPIError.invalidSession
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        true
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
            if ProviderInteractionContext.current == .userInitiated { return true }
            return TraeCookieImporter.hasSession()
        }
        return false
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        let cookieSession = try TraeCookieImporter.importSession()
        Self.log.debug("Found Trae session in \(cookieSession.sourceLabel)")

        let session = TraeSessionInfo(from: cookieSession)
        let snapshot = try await TraeUsageFetcher.fetchUsage(session: session)
        CookieHeaderCache.store(
            provider: .trae,
            cookieHeader: session.cookieHeader,
            sourceLabel: cookieSession.sourceLabel)
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

private enum TraeCookieHeader {
    static func csrfToken(from cookieHeader: String) -> String? {
        self.value(named: "passport_csrf_token", in: cookieHeader)
    }

    static func cloudideSession(from cookieHeader: String) -> String? {
        self.value(named: "X-Cloudide-Session", in: cookieHeader)
    }

    private static func value(named name: String, in cookieHeader: String) -> String? {
        cookieHeader
            .split(separator: ";")
            .compactMap { part -> String? in
                let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2 else { return nil }
                let cookieName = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
                guard cookieName == name else { return nil }
                return pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first
    }
}
