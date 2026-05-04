import Foundation

public enum ProviderTokenSource: String, Sendable {
    case environment
    case authFile
}

public struct ProviderTokenResolution: Sendable {
    public let token: String
    public let source: ProviderTokenSource

    public init(token: String, source: ProviderTokenSource) {
        self.token = token
        self.source = source
    }
}

public enum ProviderTokenResolver {
    public static func zaiToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.zaiResolution(environment: environment)?.token
    }

    public static func syntheticToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.syntheticResolution(environment: environment)?.token
    }

    public static func copilotToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.copilotResolution(environment: environment)?.token
    }

    public static func minimaxToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.minimaxTokenResolution(environment: environment)?.token
    }

    public static func alibabaToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.alibabaTokenResolution(environment: environment)?.token
    }

    public static func minimaxCookie(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.minimaxCookieResolution(environment: environment)?.token
    }

    public static func kimiAuthToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.kimiAuthResolution(environment: environment)?.token
    }

    public static func kimiK2Token(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.kimiK2Resolution(environment: environment)?.token
    }

    public static func kiloToken(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        authFileURL: URL? = nil) -> String?
    {
        self.kiloResolution(environment: environment, authFileURL: authFileURL)?.token
    }

    public static func warpToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.warpResolution(environment: environment)?.token
    }

    public static func openRouterToken(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        self.openRouterResolution(environment: environment)?.token
    }

    public static func perplexitySessionToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.perplexityResolution(environment: environment)?.token
    }

    public static func zaiResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(ZaiSettingsReader.apiToken(environment: environment))
    }

    public static func syntheticResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(SyntheticSettingsReader.apiKey(environment: environment))
    }

    public static func copilotResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(self.cleaned(environment["COPILOT_API_TOKEN"]))
    }

    public static func minimaxTokenResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(MiniMaxAPISettingsReader.apiToken(environment: environment))
    }

    public static func alibabaTokenResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(AlibabaCodingPlanSettingsReader.apiToken(environment: environment))
    }

    public static func minimaxCookieResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(MiniMaxSettingsReader.cookieHeader(environment: environment))
    }

    public static func kimiAuthResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(KimiSettingsReader.authToken(environment: environment))
    }

    public static func kimiK2Resolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(KimiK2SettingsReader.apiKey(environment: environment))
    }

    public static func kiloResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        authFileURL: URL? = nil) -> ProviderTokenResolution?
    {
        if let resolution = self.resolveEnv(KiloSettingsReader.apiKey(environment: environment)) {
            return resolution
        }
        if let token = KiloSettingsReader.authToken(authFileURL: authFileURL) {
            return ProviderTokenResolution(token: token, source: .authFile)
        }
        return nil
    }

    public static func warpResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(WarpSettingsReader.apiKey(environment: environment))
    }

    public static func openRouterResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(OpenRouterSettingsReader.apiToken(environment: environment))
    }

    public static func perplexityResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(PerplexitySettingsReader.sessionToken(environment: environment))
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'"))
        {
            value.removeFirst()
            value.removeLast()
        }

        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public static func qwenToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.qwenResolution(environment: environment)?.token
    }

    public static func doubaoToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.doubaoResolution(environment: environment)?.token
    }

    public static func stepfunToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.stepfunResolution(environment: environment)?.token
    }

    public static func traeToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.traeResolution(environment: environment)?.token
    }

    public static func mimoToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.mimoResolution(environment: environment)?.token
    }

    public static func zenmuxToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.zenmuxResolution(environment: environment)?.token
    }

    public static func aigocodeToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.aigocodeResolution(environment: environment)?.token
    }

    public static func qwenResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(QwenSettingsReader.apiKey(environment: environment))
    }

    public static func doubaoResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(DoubaoSettingsReader.apiKey(environment: environment))
    }

    public static func stepfunResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(StepFunSettingsReader.apiKey(environment: environment))
    }

    public static func traeResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(TraeSettingsReader.apiKey(environment: environment))
    }

    public static func mimoResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(MiMoSettingsReader.apiKey(environment: environment))
    }

    public static func zenmuxResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(ZenmuxSettingsReader.apiKey(environment: environment))
    }

    public static func aigocodeResolution(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> ProviderTokenResolution?
    {
        self.resolveEnv(AigoCodeSettingsReader.apiKey(environment: environment))
    }

    private static func resolveEnv(_ token: String?) -> ProviderTokenResolution? {
        guard let token else { return nil }
        return ProviderTokenResolution(token: token, source: .environment)
    }
}
