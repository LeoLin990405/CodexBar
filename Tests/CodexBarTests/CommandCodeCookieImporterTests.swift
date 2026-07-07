import Foundation
import Testing
@testable import CodexBarCore

#if os(macOS)
struct CommandCodeCookieImporterTests {
    @Test
    func `preferred session chooses recognized command code session cookie`() throws {
        let fallbackGa = try #require(Self.cookie(name: "_ga", value: "ga-value"))
        let fallbackStripe = try #require(Self.cookie(name: "stripe_mid", value: "stripe-value"))
        let fallback = CommandCodeCookieImporter.SessionInfo(
            cookies: [fallbackGa, fallbackStripe],
            sourceLabel: "Chrome")
        let recognizedCookie = try #require(
            Self.cookie(name: "__Secure-commandcode_prod_.session_token", value: "prod-token"))
        let recognized = CommandCodeCookieImporter.SessionInfo(
            cookies: [recognizedCookie],
            sourceLabel: "Vivaldi")

        let preferred = try #require(CommandCodeCookieImporter.preferredSession(from: [fallback, recognized]))
        #expect(preferred.sourceLabel == "Vivaldi")
        #expect(preferred.sessionCookie?.name == "__Secure-commandcode_prod_.session_token")
    }

    @Test
    func `preferred session falls back to first session when no recognized cookie exists`() throws {
        let firstCookie = try #require(Self.cookie(name: "_ga", value: "ga-value"))
        let first = CommandCodeCookieImporter.SessionInfo(
            cookies: [firstCookie],
            sourceLabel: "Chrome")
        let secondCookie = try #require(Self.cookie(name: "session_data", value: "data-value"))
        let second = CommandCodeCookieImporter.SessionInfo(
            cookies: [secondCookie],
            sourceLabel: "Vivaldi")

        let preferred = try #require(CommandCodeCookieImporter.preferredSession(from: [first, second]))
        #expect(preferred.sourceLabel == "Chrome")
        #expect(preferred.sessionCookie == nil)
    }

    private static func cookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "commandcode.ai",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
        ])
    }
}
#endif
