import Foundation

public enum CodexBarConfigIssueSeverity: String, Codable, Sendable {
    case warning
    case error
}

public struct CodexBarConfigIssue: Codable, Sendable, Equatable {
    public let severity: CodexBarConfigIssueSeverity
    public let provider: UsageProvider?
    public let field: String?
    public let code: String
    public let message: String

    public init(
        severity: CodexBarConfigIssueSeverity,
        provider: UsageProvider?,
        field: String?,
        code: String,
        message: String)
    {
        self.severity = severity
        self.provider = provider
        self.field = field
        self.code = code
        self.message = message
    }
}

public enum CodexBarConfigValidator {
    public static func validate(_ config: CodexBarConfig) -> [CodexBarConfigIssue] {
        var issues: [CodexBarConfigIssue] = []

        if config.version != CodexBarConfig.currentVersion {
            issues.append(CodexBarConfigIssue(
                severity: .error,
                provider: nil,
                field: "version",
                code: "version_mismatch",
                message: "不支持的配置版本 \(config.version)。"))
        }

        for entry in config.providers {
            self.validateProvider(entry, issues: &issues)
        }

        return issues
    }

    private static func validateProvider(_ entry: ProviderConfig, issues: inout [CodexBarConfigIssue]) {
        let provider = entry.id
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider)
        let supportedSources = descriptor.fetchPlan.sourceModes
        let supportsWeb = supportedSources.contains(.auto) || supportedSources.contains(.web)
        let supportsAPI = supportedSources.contains(.api)

        if let source = entry.source, !supportedSources.contains(source) {
            issues.append(CodexBarConfigIssue(
                severity: .error,
                provider: provider,
                field: "source",
                code: "unsupported_source",
                message: "\(provider.rawValue) 不支持来源 \(source.rawValue)。"))
        }

        if let apiKey = entry.apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !supportsAPI {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "apiKey",
                code: "api_key_unused",
                message: "已设置 apiKey，但 \(provider.rawValue) 不支持 api 来源。"))
        }

        if let source = entry.source, source == .api, !supportsAPI {
            issues.append(CodexBarConfigIssue(
                severity: .error,
                provider: provider,
                field: "source",
                code: "api_source_unsupported",
                message: "\(provider.rawValue) 不支持 api 来源。"))
        }

        if let source = entry.source, source == .api,
           entry.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "apiKey",
                code: "api_key_missing",
                message: "已选择 api 来源，但 \(provider.rawValue) 缺少 apiKey。"))
        }

        if entry.cookieSource != nil, !supportsWeb {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "cookieSource",
                code: "cookie_source_unused",
                message: "已设置 cookieSource，但 \(provider.rawValue) 不使用网页 Cookie。"))
        }

        if let cookieHeader = entry.cookieHeader,
           !cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !supportsWeb
        {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "cookieHeader",
                code: "cookie_header_unused",
                message: "已设置 cookieHeader，但 \(provider.rawValue) 不使用网页 Cookie。"))
        }

        if let cookieSource = entry.cookieSource,
           cookieSource == .manual,
           entry.cookieHeader?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "cookieHeader",
                code: "cookie_header_missing",
                message: "cookieSource 已设为 manual，但 \(provider.rawValue) 缺少 cookieHeader。"))
        }

        if let region = entry.region, !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch provider {
            case .minimax:
                if MiniMaxAPIRegion(rawValue: region) == nil {
                    issues.append(CodexBarConfigIssue(
                        severity: .error,
                        provider: provider,
                        field: "region",
                        code: "invalid_region",
                        message: "\(region) 不是有效的 MiniMax 区域。"))
                }
            case .zai:
                if ZaiAPIRegion(rawValue: region) == nil {
                    issues.append(CodexBarConfigIssue(
                        severity: .error,
                        provider: provider,
                        field: "region",
                        code: "invalid_region",
                        message: "\(region) 不是有效的 z.ai 区域。"))
                }
            case .alibaba:
                if AlibabaCodingPlanAPIRegion(rawValue: region) == nil {
                    issues.append(CodexBarConfigIssue(
                        severity: .error,
                        provider: provider,
                        field: "region",
                        code: "invalid_region",
                        message: "\(region) 不是有效的 Alibaba Coding Plan 区域。"))
                }
            default:
                issues.append(CodexBarConfigIssue(
                    severity: .warning,
                    provider: provider,
                    field: "region",
                    code: "region_unused",
                    message: "已设置 region，但 \(provider.rawValue) 不使用区域。"))
            }
        }

        if let workspaceID = entry.workspaceID,
           !workspaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           provider != .opencode,
           provider != .opencodego
        {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "workspaceID",
                code: "workspace_unused",
                message: "已设置 workspaceID，但只有 opencode 和 opencodego 支持 workspaceID。"))
        }

        if let tokenAccounts = entry.tokenAccounts, !tokenAccounts.accounts.isEmpty,
           TokenAccountSupportCatalog.support(for: provider) == nil
        {
            issues.append(CodexBarConfigIssue(
                severity: .warning,
                provider: provider,
                field: "tokenAccounts",
                code: "token_accounts_unused",
                message: "已设置 tokenAccounts，但 \(provider.rawValue) 不支持 token 账号。"))
        }
    }
}
