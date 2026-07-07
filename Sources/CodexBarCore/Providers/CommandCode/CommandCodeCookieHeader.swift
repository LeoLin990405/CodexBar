import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A resolved CommandCode session cookie ready to be sent on `Cookie:` headers.
///
/// Command Code's API (api.commandcode.ai) authenticates with the session cookie set
/// by commandcode.ai. Older deployments used better-auth's default cookie names; newer
/// production deployments namespace the cookie under `commandcode_prod_`.
public struct CommandCodeCookieOverride: Sendable, Equatable {
    public let name: String
    public let token: String

    public init(name: String, token: String) {
        self.name = name
        self.token = token
    }

    /// `Cookie: name=value` header value.
    public var headerValue: String {
        "\(self.name)=\(self.token)"
    }
}

public enum CommandCodeCookieHeader {
    /// Cookie names observed across older better-auth defaults and newer
    /// Command Code production deployments.
    public static let supportedSessionCookieNames = [
        "__Host-commandcode_prod_.session_token",
        "__Secure-commandcode_prod_.session_token",
        "commandcode_prod_.session_token",
        "__Host-better-auth.session_token",
        "__Secure-better-auth.session_token",
        "better-auth.session_token",
    ]

    /// Extract a session cookie from a list of `HTTPCookie` records.
    public static func sessionCookie(from cookies: [HTTPCookie]) -> CommandCodeCookieOverride? {
        let pairs = cookies.map { (name: $0.name, value: $0.value) }
        return self.extractSessionCookie(from: pairs)
    }

    /// Parse a raw `Cookie:` header (or bare token) and extract the session value.
    public static func override(from raw: String?) -> CommandCodeCookieOverride? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // Bare token — assume the current production cookie name.
        if !raw.contains("="), !raw.contains(";") {
            return CommandCodeCookieOverride(
                name: "__Secure-commandcode_prod_.session_token",
                token: raw)
        }

        return self.extractSessionCookie(fromHeader: raw)
    }

    private static func extractSessionCookie(fromHeader header: String) -> CommandCodeCookieOverride? {
        var pairs: [(name: String, value: String)] = []
        for chunk in header.split(separator: ";") {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            pairs.append((name: key, value: value))
        }
        return self.extractSessionCookie(from: pairs)
    }

    private static func extractSessionCookie(from pairs: [(name: String, value: String)])
    -> CommandCodeCookieOverride? {
        var byLowerName: [String: (name: String, value: String)] = [:]
        for pair in pairs {
            byLowerName[pair.name.lowercased()] = pair
        }
        for expected in self.supportedSessionCookieNames {
            if let match = byLowerName[expected.lowercased()] {
                return CommandCodeCookieOverride(name: match.name, token: match.value)
            }
        }
        return nil
    }
}
