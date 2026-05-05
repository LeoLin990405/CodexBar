import Foundation

public struct AlibabaCodingPlanSettingsReader: Sendable {
    public static let apiTokenKey = "ALIBABA_CODING_PLAN_API_KEY"
    public static let cookieHeaderKey = "ALIBABA_CODING_PLAN_COOKIE"
    public static let hostKey = "ALIBABA_CODING_PLAN_HOST"
    public static let quotaURLKey = "ALIBABA_CODING_PLAN_QUOTA_URL"

    public static func apiToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.apiTokenKey])
    }

    public static func hostOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.hostKey])
    }

    public static func cookieHeader(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.cookieHeaderKey])
    }

    public static func quotaURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = self.cleaned(environment[self.quotaURLKey]) else { return nil }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(raw)")
    }

    static func cleaned(_ raw: String?) -> String? {
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
}

public enum AlibabaCodingPlanSettingsError: LocalizedError, Sendable {
    case missingToken
    case missingCookie(details: String? = nil)
    case invalidCookie

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "未找到 Alibaba Coding Plan API key。" +
                "请在 ~/.codexbar/config.json 设置 apiKey，或设置 ALIBABA_CODING_PLAN_API_KEY。"
        case let .missingCookie(details):
            let base = "浏览器中未找到 Alibaba Coding Plan 会话 Cookie。" +
                "如果使用 Safari，请为 CodexBar/终端开启完全磁盘访问权限，或手动粘贴 Cookie header。"
            guard let details, !details.isEmpty else { return base }
            return "\(base) \(details)"
        case .invalidCookie:
            return "Alibaba Coding Plan Cookie header 无效。"
        }
    }
}
