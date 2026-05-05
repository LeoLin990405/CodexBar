import Foundation

extension TokenAccountSupportCatalog {
    static let supportByProvider: [UsageProvider: TokenAccountSupport] = [
        .claude: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存 Claude sessionKey Cookie 或 OAuth access token。",
            placeholder: "粘贴 sessionKey 或 OAuth token…",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: "sessionKey"),
        .zai: TokenAccountSupport(
            title: "API token",
            subtitle: "保存在 CodexBar 配置文件中。",
            placeholder: "粘贴 token…",
            injection: .environment(key: ZaiSettingsReader.apiTokenKey),
            requiresManualCookieSource: false,
            cookieName: nil),
        .cursor: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 Cursor Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .opencode: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 OpenCode Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .opencodego: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 OpenCode Go Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .factory: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 Factory Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .minimax: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 MiniMax Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .augment: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 Augment Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .ollama: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 Ollama Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
        .abacus: TokenAccountSupport(
            title: "会话 token",
            subtitle: "保存多个 Abacus AI Cookie header。",
            placeholder: "Cookie: …",
            injection: .cookieHeader,
            requiresManualCookieSource: true,
            cookieName: nil),
    ]
}
