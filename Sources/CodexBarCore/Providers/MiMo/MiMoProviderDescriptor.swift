import CodexBarMacroSupport
import Foundation

#if os(macOS)
import SweetCookieKit
#endif

@ProviderDescriptorRegistration
@ProviderDescriptorDefinition
public enum MiMoProviderDescriptor {
    static func makeDescriptor() -> ProviderDescriptor {
        #if os(macOS)
        let browserOrder: BrowserCookieImportOrder = [
            .chrome,
            .chromeBeta,
            .chromeCanary,
        ]
        #else
        let browserOrder: BrowserCookieImportOrder? = nil
        #endif

        return ProviderDescriptor(
            id: .mimo,
            metadata: ProviderMetadata(
                id: .mimo,
                displayName: "小米的 Mihomo",
                sessionLabel: "Credits 余额",
                weeklyLabel: "窗口",
                opusLabel: nil,
                supportsOpus: false,
                supportsCredits: true,
                creditsHint: "Token plan credits usage.",
                toggleTitle: "显示小米的 Mihomo token 套餐与余额",
                cliName: "mimo",
                defaultEnabled: false,
                isPrimaryProvider: false,
                usesAccountFallback: false,
                browserCookieOrder: browserOrder,
                dashboardURL: "https://platform.xiaomimimo.com/#/console/balance",
                statusPageURL: nil),
            branding: ProviderBranding(
                iconStyle: .mimo,
                iconResourceName: "ProviderIcon-mimo",
                color: ProviderColor(red: 1.0, green: 105 / 255, blue: 0)),
            tokenCost: ProviderTokenCostConfig(
                supportsTokenCost: false,
                noDataMessage: { "小米的 Mihomo 暂不支持费用摘要。" }),
            fetchPlan: ProviderFetchPlan(
                sourceModes: [.auto, .web, .api],
                pipeline: ProviderFetchPipeline(resolveStrategies: self.resolveStrategies)),
            cli: ProviderCLIConfig(
                name: "mimo",
                aliases: ["xiaomi-mimo"],
                versionDetector: nil))
    }

    private static func resolveStrategies(context: ProviderFetchContext) async -> [any ProviderFetchStrategy] {
        switch context.sourceMode {
        case .api:
            [MiMoAPIFetchStrategy()]
        case .web:
            [MiMoWebFetchStrategy()]
        case .auto:
            [MiMoAPIFetchStrategy(), MiMoWebFetchStrategy()]
        case .cli, .oauth:
            []
        }
    }
}

struct MiMoAPIFetchStrategy: ProviderFetchStrategy {
    let id: String = "mimo.api"
    let kind: ProviderFetchKind = .apiToken

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        ProviderTokenResolver.mimoResolution(environment: context.env) != nil
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard let apiKey = ProviderTokenResolver.mimoToken(environment: context.env) else {
            throw MiMoSettingsError.missingAPIKey
        }
        let usage = try await MiMoUsageFetcher.fetchAPIUsage(
            apiKey: apiKey,
            environment: context.env)
        return self.makeResult(usage: usage, sourceLabel: "api")
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        true
    }
}

struct MiMoWebFetchStrategy: ProviderFetchStrategy {
    let id: String = "mimo.web"
    let kind: ProviderFetchKind = .web

    func isAvailable(_ context: ProviderFetchContext) async -> Bool {
        guard context.settings?.mimo?.cookieSource != .off else { return false }
        if context.settings?.mimo?.cookieSource == .manual {
            return Self.resolveManualCookieHeader(context: context) != nil
        }
        if Self.resolveManualCookieHeader(context: context) != nil {
            return true
        }

        #if os(macOS)
        if let cached = CookieHeaderCache.load(provider: .mimo),
           MiMoCookieHeader.normalizedHeader(from: cached.cookieHeader) != nil
        {
            return true
        }
        return MiMoCookieImporter.hasSession(browserDetection: context.browserDetection)
        #else
        return false
        #endif
    }

    func fetch(_ context: ProviderFetchContext) async throws -> ProviderFetchResult {
        guard context.settings?.mimo?.cookieSource != .off else {
            throw MiMoSettingsError.missingCookie
        }
        if context.settings?.mimo?.cookieSource == .manual {
            guard let manualCookie = Self.resolveManualCookieHeader(context: context) else {
                throw MiMoSettingsError.invalidCookie
            }
            let snapshot = try await MiMoUsageFetcher.fetchUsage(
                cookieHeader: manualCookie,
                environment: context.env)
            return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
        }
        if let manualCookie = Self.resolveManualCookieHeader(context: context) {
            let snapshot = try await MiMoUsageFetcher.fetchUsage(
                cookieHeader: manualCookie,
                environment: context.env)
            return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
        }

        #if os(macOS)
        var lastError: Error?

        if let cached = CookieHeaderCache.load(provider: .mimo),
           let cachedHeader = MiMoCookieHeader.normalizedHeader(from: cached.cookieHeader)
        {
            do {
                let snapshot = try await MiMoUsageFetcher.fetchUsage(
                    cookieHeader: cachedHeader,
                    environment: context.env)
                return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
            } catch {
                guard Self.shouldRetryNextSession(for: error) else {
                    throw error
                }
                CookieHeaderCache.clear(provider: .mimo)
                lastError = error
            }
        }

        let sessions = try MiMoCookieImporter.importSessions(browserDetection: context.browserDetection)
        guard !sessions.isEmpty else {
            if let lastError { throw lastError }
            throw MiMoSettingsError.missingCookie
        }

        for session in sessions {
            do {
                let snapshot = try await MiMoUsageFetcher.fetchUsage(
                    cookieHeader: session.cookieHeader,
                    environment: context.env)
                CookieHeaderCache.store(
                    provider: .mimo,
                    cookieHeader: session.cookieHeader,
                    sourceLabel: session.sourceLabel)
                return self.makeResult(usage: snapshot.toUsageSnapshot(), sourceLabel: "web")
            } catch {
                guard Self.shouldRetryNextSession(for: error) else {
                    throw error
                }
                lastError = error
                continue
            }
        }

        if let lastError { throw lastError }
        throw MiMoSettingsError.missingCookie
        #else
        throw MiMoSettingsError.missingCookie
        #endif
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }

    private static func resolveManualCookieHeader(context: ProviderFetchContext) -> String? {
        guard context.settings?.mimo?.cookieSource == .manual else { return nil }
        return MiMoCookieHeader.normalizedHeader(from: context.settings?.mimo?.manualCookieHeader)
    }

    private static func shouldRetryNextSession(for error: Error) -> Bool {
        if error is DecodingError {
            return true
        }
        guard let mimoError = error as? MiMoUsageError else {
            return false
        }
        switch mimoError {
        case .invalidCredentials, .loginRequired, .parseFailed:
            return true
        case .networkError:
            return false
        }
    }
}
