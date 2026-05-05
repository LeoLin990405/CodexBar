import Foundation

public struct ZaiSettingsReader: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.zaiSettings)

    public static let apiTokenKey = "Z_AI_API_KEY"
    public static let apiTokenAliasKeys = [
        "ZHIPU_API_KEY",
        "ZHIPUAI_API_KEY",
        "GLM_API_KEY",
        "BIGMODEL_API_KEY",
    ]
    public static let apiHostKey = "Z_AI_API_HOST"
    public static let quotaURLKey = "Z_AI_QUOTA_URL"

    public static func apiToken(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        if let token = self.cleaned(environment[apiTokenKey]) { return token }
        for key in self.apiTokenAliasKeys {
            if let token = self.cleaned(environment[key]) { return token }
        }
        return nil
    }

    public static func apiHost(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> String?
    {
        self.cleaned(environment[self.apiHostKey])
    }

    public static func quotaURL(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> URL?
    {
        guard let raw = self.cleaned(environment[quotaURLKey]) else { return nil }
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

public enum ZaiSettingsError: LocalizedError, Sendable {
    case missingToken

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "z.ai API token not found. Set apiKey in ~/.codexbar/config.json or Z_AI_API_KEY/ZHIPU_API_KEY/GLM_API_KEY/BIGMODEL_API_KEY."
        }
    }
}
