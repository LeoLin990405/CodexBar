import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(macOS)
import SweetCookieKit
#endif

/// Fetches Doubao Coding Plan quota via the Volcengine web console API
/// (`GetCodingPlanUsage`), using the user's browser session cookies.
///
/// The public API (api/coding/v3/chat/completions) does not expose quota
/// headers for coding-plan accounts, so we piggyback on the console's own
/// internal endpoint the same way StepFun/AigoCode scrape their dashboards.
public enum DoubaoConsoleFetcher {
    public static let endpoint = URL(
        string: "https://console.volcengine.com/api/top/ark/cn-beijing/2024-01-01/GetCodingPlanUsage?")!

    public static let referer =
        "https://console.volcengine.com/ark/region:ark+cn-beijing/openManagement?LLM=%7B%7D&advancedActiveKey=subscribe"

    public static let cookieDomains = ["console.volcengine.com", "volcengine.com"]

    public struct QuotaLevel: Sendable, Equatable {
        public let level: String
        public let percent: Double
        public let resetAt: Date?

        public init(level: String, percent: Double, resetAt: Date?) {
            self.level = level
            self.percent = percent
            self.resetAt = resetAt
        }
    }

    public struct Result: Sendable {
        public let status: String
        public let updatedAt: Date
        public let quotas: [QuotaLevel]

        public func quota(level: String) -> QuotaLevel? {
            self.quotas.first { $0.level == level }
        }
    }

    public enum Error: Swift.Error {
        case noCookies
        case missingCSRF
        case networkError(String)
        case apiError(Int, String)
        case parseError(String)
    }

    // MARK: - macOS: cookie-backed fetch

    #if os(macOS)
    nonisolated(unsafe) static var importSessionsOverrideForTesting:
        ((BrowserDetection, ((String) -> Void)?) throws -> [SessionInfo])?

    public struct SessionInfo: Sendable {
        public let cookies: [HTTPCookie]
        public let sourceLabel: String
    }

    public static func importSessions(
        browserDetection: BrowserDetection,
        logger: ((String) -> Void)? = nil) throws -> [SessionInfo]
    {
        if let override = importSessionsOverrideForTesting {
            return try override(browserDetection, logger)
        }
        let log: (String) -> Void = { msg in logger?("[doubao-console] \(msg)") }
        let cookieClient = BrowserCookieClient()
        let order = Browser.defaultImportOrder
        let installed = order.cookieImportCandidates(using: browserDetection)
        var sessions: [SessionInfo] = []
        for browserSource in installed {
            do {
                let query = BrowserCookieQuery(domains: Self.cookieDomains)
                let records = try cookieClient.records(matching: query, in: browserSource, logger: log)
                for group in records {
                    let cookies = BrowserCookieClient.makeHTTPCookies(group.records, origin: query.origin)
                    guard !cookies.isEmpty else { continue }
                    sessions.append(SessionInfo(cookies: cookies, sourceLabel: group.label))
                }
            } catch {
                log("\(browserSource.displayName) cookie import failed: \(error.localizedDescription)")
            }
        }
        return sessions
    }

    public static func fetch(
        browserDetection: BrowserDetection,
        logger: ((String) -> Void)? = nil) async throws -> Result
    {
        let sessions = try self.importSessions(browserDetection: browserDetection, logger: logger)
        guard !sessions.isEmpty else { throw Error.noCookies }
        var lastError: Swift.Error?
        for session in sessions {
            do {
                return try await self.fetch(cookies: session.cookies)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? Error.noCookies
    }

    static func fetch(cookies: [HTTPCookie]) async throws -> Result {
        let cookieHeader = cookies
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        guard let csrf = cookies.first(where: { $0.name == "csrfToken" })?.value else {
            throw Error.missingCSRF
        }
        return try await self.fetch(cookieHeader: cookieHeader, csrfToken: csrf)
    }
    #endif

    // MARK: - Cross-platform: direct request (used by tests and Linux)

    public static func fetch(cookieHeader: String, csrfToken: String) async throws -> Result {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://console.volcengine.com", forHTTPHeaderField: "Origin")
        request.setValue(Self.referer, forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) CodexBar/1.0",
            forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Error.networkError("non-HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw Error.apiError(http.statusCode, String(body.prefix(200)))
        }
        return try self.parse(data: data)
    }

    static func parse(data: Data) throws -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["Result"] as? [String: Any]
        else {
            throw Error.parseError("missing Result")
        }
        let status = result["Status"] as? String ?? "Unknown"
        let updatedTs = result["UpdateTimestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        guard let quotaArray = result["QuotaUsage"] as? [[String: Any]] else {
            throw Error.parseError("missing QuotaUsage")
        }
        let quotas = quotaArray.compactMap { entry -> QuotaLevel? in
            guard let level = entry["Level"] as? String else { return nil }
            let percent = (entry["Percent"] as? Double) ?? 0
            let resetAt: Date? = (entry["ResetTimestamp"] as? TimeInterval)
                .map { Date(timeIntervalSince1970: $0) }
            return QuotaLevel(level: level, percent: percent, resetAt: resetAt)
        }
        return Result(
            status: status,
            updatedAt: Date(timeIntervalSince1970: updatedTs),
            quotas: quotas)
    }
}
