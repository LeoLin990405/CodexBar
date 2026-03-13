#if os(macOS)
import Foundation
import SweetCookieKit
import WebKit

/// Imports AigoCode session cookies from browsers (Chrome, Safari, etc.)
/// and injects them into a non-persistent WKWebsiteDataStore for dashboard scraping.
public enum AigoCodeCookieImporter {
    private static let log = CodexBarLog.logger(LogCategories.aigocodeWeb)
    private static let cookieClient = BrowserCookieClient()
    private static let cookieDomains = ["aigocode.com", "www.aigocode.com"]
    private static let cookieImportOrder: BrowserCookieImportOrder =
        ProviderDefaults.metadata[.aigocode]?.browserCookieOrder ?? Browser.defaultImportOrder

    /// Attempts to extract AigoCode session cookies from installed browsers
    /// and returns a configured WKWebsiteDataStore ready for dashboard scraping.
    @MainActor
    public static func importCookiesIntoDataStore(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) throws -> WKWebsiteDataStore
    {
        let cookies = try self.importCookies(browserDetection: browserDetection, logger: logger)
        let store = WKWebsiteDataStore.nonPersistent()

        // Inject cookies synchronously via the cookie store
        let cookieStore = store.httpCookieStore
        for cookie in cookies {
            cookieStore.setCookie(cookie, completionHandler: nil)
        }

        return store
    }

    /// Extracts AigoCode-related HTTPCookies from the first browser that has them.
    public static func importCookies(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        let candidates = self.cookieImportOrder.cookieImportCandidates(using: browserDetection)

        for browserSource in candidates {
            do {
                let cookies = try self.importCookies(from: browserSource, logger: logger)
                if !cookies.isEmpty {
                    return cookies
                }
            } catch {
                BrowserCookieAccessGate.recordIfNeeded(error)
                self.emit(
                    "\(browserSource.displayName) cookie import failed: \(error.localizedDescription)",
                    logger: logger)
            }
        }

        throw AigoCodeCookieImportError.noCookies
    }

    /// Checks whether any browser has AigoCode session cookies.
    public static func hasSession(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) -> Bool
    {
        do {
            let cookies = try self.importCookies(browserDetection: browserDetection, logger: logger)
            return !cookies.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Private

    private static func importCookies(
        from browserSource: Browser,
        logger: ((String) -> Void)? = nil) throws -> [HTTPCookie]
    {
        let query = BrowserCookieQuery(domains: self.cookieDomains)
        let log: (String) -> Void = { msg in self.emit(msg, logger: logger) }
        let sources = try Self.cookieClient.records(
            matching: query,
            in: browserSource,
            logger: log)

        var allCookies: [HTTPCookie] = []
        for source in sources {
            let httpCookies = BrowserCookieClient.makeHTTPCookies(source.records, origin: query.origin)
            guard !httpCookies.isEmpty else { continue }

            // Check for Supabase auth cookies (sb-*-auth-token*)
            let hasAuth = httpCookies.contains { cookie in
                cookie.name.hasPrefix("sb-") && cookie.name.contains("auth-token")
            }

            if hasAuth {
                log("Found Supabase auth cookies in \(source.label) (\(httpCookies.count) cookies)")
                allCookies.append(contentsOf: httpCookies)
            }
        }

        if allCookies.isEmpty {
            log("No Supabase auth cookies found in \(browserSource.displayName)")
        }

        return allCookies
    }

    private static func emit(_ message: String, logger: ((String) -> Void)?) {
        logger?("[aigocode-cookie] \(message)")
        self.log.debug(message)
    }
}

enum AigoCodeCookieImportError: LocalizedError {
    case noCookies

    var errorDescription: String? {
        switch self {
        case .noCookies:
            "No AigoCode session cookies found in browsers. Log in to aigocode.com in Chrome or Safari."
        }
    }
}
#endif
