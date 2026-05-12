import CodexBarMacroSupport
import Foundation

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum KimiProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        ProviderDescriptor(
            id: .kimi,
            metadata: ProviderMetadata(
                id: .kimi,
                displayName: "月之暗面 Kimi",
                sessionLabel: "每周",
                weeklyLabel: "速率限制",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: false,
                creditsHint: "",
                toggleTitle: "显示月之暗面 Kimi 用量",
                cliName: "kimi",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: nil,
                dashboardURL: "https://www.kimi.com/code/console",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .kimi,
                iconResourceName: "ProviderIcon-kimi",
                color: ProviderColor(red: 254 / 255, green: 96 / 255, blue: 60 / 255)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "月之暗面 Kimi 暂不支持费用摘要。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "kimi",
                aliases: ["kimi-ai"],
                versionDetector: nil))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .api:
            [KimiTokenFetchStrategy()]
        case .web:
            [KimiWebFetchStrategy()]
        case .auto:
            [KimiTokenFetchStrategy(), KimiWebFetchStrategy()]
        case .cli, .oauth:
            []
        }
    }
}

struct KimiTokenFetchStrategy: ProviderFetchStrategy {
    let id: String = "kimi.token"
    let kind: ProviderFetchKind = .apiToken
    private let fetchUsage: @Sendable (String) async throws -> KimiUsageSnapshot

    init(fetchUsage: @escaping @Sendable (String) async throws -> KimiUsageSnapshot = { token in
        try await KimiUsageFetcher.fetchUsage(authToken: token)
    }) {
        self.fetchUsage = fetchUsage
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        self.resolveToken(context: context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let token = self.resolveToken(context: context) else {
            throw KimiAPIError.missingToken
        }

        let snapshot = try await self.fetchUsage(token)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "token")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        // Every token-strategy error (missing/invalid manual/env token, network blip)
        // must fall through so the web strategy can try browser cookies + localStorage.
        true
    }

    private func resolveToken(context: ProviderFetchContext) -> String? {
        if let override = KimiCookieHeader.resolveCookieOverride(context: context) {
            return override.token
        }
        return ProviderTokenResolver.kimiAuthToken(environment: context.env)
    }
}

struct KimiWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "kimi.web"
    let kind: ProviderFetchKind = .web
    private static let log = CodexBarLog.logger(LogCategories.kimiWeb)
    private let fetchUsage: @Sendable (String) async throws -> KimiUsageSnapshot
    private let browserTokenResolver: @Sendable (ProviderFetchContext) -> String?

    init(
        fetchUsage: @escaping @Sendable (String) async throws -> KimiUsageSnapshot = { token in
            try await KimiUsageFetcher.fetchUsage(authToken: token)
        },
        browserTokenResolver: @escaping @Sendable (ProviderFetchContext) -> String? = { context in
            KimiWebFetchStrategy.resolveBrowserToken(context: context)
        })
    {
        self.fetchUsage = fetchUsage
        self.browserTokenResolver = browserTokenResolver
    }

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        self.browserTokenResolver(context) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let token = self.browserTokenResolver(context) else {
            throw KimiAPIError.missingToken
        }

        let snapshot = try await self.fetchUsage(token)
        return self.makeResult(
            usage: snapshot.toUsageSnapshot(),
            sourceLabel: "web")
    }

    func shouldFallback(on error: Error, context: ProviderFetchContext) -> Bool {
        if case KimiAPIError.missingToken = error { return false }
        if case KimiAPIError.invalidToken = error { return false }
        return true
    }

    private static func resolveBrowserToken(context: ProviderFetchContext) -> String? {
        // Try browser cookie import when auto mode is enabled
        #if os(macOS)
        if context.settings?.kimi?.cookieSource != .off {
            // Try cookies first (legacy kimi-auth cookie)
            do {
                let session = try KimiCookieImporter.importSession(browserDetection: context.browserDetection)
                if let token = session.authToken {
                    return token
                }
            } catch {
                // No browser cookies found
            }

            // Try localStorage (current: access_token JWT)
            if let lsSession = KimiLocalStorageImporter.importSession(browserDetection: context.browserDetection) {
                return lsSession.accessToken
            }
        }
        #endif
        return nil
    }
}
