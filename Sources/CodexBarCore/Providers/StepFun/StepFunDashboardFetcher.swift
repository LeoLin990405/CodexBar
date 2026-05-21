#if os(macOS)
import Foundation
import WebKit

/// Scrapes the StepFun plan-subscribe dashboard to extract Step Plan usage data.
///
/// StepFun's plan API (GetStepPlanStatus, QueryStepPlanRateLimit) requires browser-bound
/// Oasis-Token that rejects non-browser HTTP clients ("embezzled" error). Using WKWebView
/// ensures the TLS fingerprint matches a real browser, bypassing this restriction.
@MainActor
public struct StepFunDashboardFetcher {
    public enum FetchError: LocalizedError {
        case loginRequired
        case noUsageData(body: String)
        case timeout

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                "阶跃星辰网页访问需要登录。请打开设置 → 阶跃星辰 → 在浏览器中登录。"
            case let .noUsageData(body):
                "未找到阶跃星辰仪表盘数据。Body sample: \(body.prefix(200))"
            case .timeout:
                "阶跃星辰仪表盘加载超时。"
            }
        }
    }

    public struct DashboardSnapshot: Sendable {
        public let planName: String?
        public let planExpiry: String?
        public let fiveHourLeftPercent: Double?
        public let fiveHourResetTime: String?
        public let weeklyLeftPercent: Double?
        public let weeklyResetTime: String?
    }

    private static let log = CodexBarLog.logger(LogCategories.stepfunUsage)
    private static let dashboardURL = URL(string: "https://platform.stepfun.com/plan-subscribe")!

    public init() {}

    public func fetchDashboard(
        websiteDataStore: WKWebsiteDataStore = .default(),
        timeout: TimeInterval = 30) async throws -> DashboardSnapshot
    {
        let deadline = Date().addingTimeInterval(max(1, timeout))

        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore
        await self.primeCookies(in: websiteDataStore)

        let webView = WKWebView(frame: CGRect(x: -9999, y: -9999, width: 1200, height: 900), configuration: config)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"

        defer {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }

        _ = webView.load(URLRequest(url: Self.dashboardURL))
        Self.log.debug("Loading StepFun dashboard…")

        var lastBody = ""
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(2000))

            let scrape = try await self.scrape(webView: webView)

            if scrape.isLoginPage {
                Self.log.debug("Login page detected")
                throw FetchError.loginRequired
            }

            lastBody = scrape.bodyText

            if let snapshot = scrape.snapshot {
                Self.log.debug(
                    "Dashboard parsed: plan=\(snapshot.planName ?? "nil") " +
                        "5h=\(snapshot.fiveHourLeftPercent ?? -1)% " +
                        "weekly=\(snapshot.weeklyLeftPercent ?? -1)%")
                return snapshot
            }
        }

        throw FetchError.noUsageData(body: lastBody)
    }

    // MARK: - JavaScript Scraping

    private struct ScrapeResult {
        let isLoginPage: Bool
        let bodyText: String
        let snapshot: DashboardSnapshot?
    }

    private func primeCookies(in websiteDataStore: WKWebsiteDataStore) async {
        do {
            let session = try StepFunCookieImporter.importSession()
            for cookie in session.cookies {
                await withCheckedContinuation { continuation in
                    websiteDataStore.httpCookieStore.setCookie(cookie) {
                        continuation.resume()
                    }
                }
            }
            Self.log.debug("Imported StepFun cookies from \(session.sourceLabel)")
        } catch {
            Self.log.debug("StepFun browser cookie import skipped: \(error.localizedDescription)")
        }
    }

    private func scrape(webView: WKWebView) async throws -> ScrapeResult {
        let js = """
        (() => {
            const href = window.location.href;
            const rawBody = document.body ? document.body.innerText : '';
            const body = rawBody
                .replace(/\\u00a0/g, ' ')
                .replace(/[\\u200b\\u200c\\u200d\\ufeff]/g, '')
                .replace(/[ \\t\\r\\n]+/g, ' ')
                .trim();

            // Detect login/redirect page
            const isLogin = href.includes('need_login_in=1') ||
                (body.includes('登录') && !body.includes('订阅详情'));

            if (isLogin) {
                return JSON.stringify({ isLogin: true, body: body.substring(0, 500) });
            }

            const pct = (match) => match ? parseFloat(match[1]) : null;

            // Extract plan name: "你当前订阅的版本为Plus Plan，有..."
            const planMatch = body.match(/订阅的版本为\\s*([^，,。；;]*?\\s*Plan)/i) ||
                body.match(/当前订阅的版本为\\s*([^，,。；;]+)/);
            const plan = planMatch ? planMatch[1].replace(/\\s+/g, ' ').trim() : null;

            // Extract expiry date: "有效期截止至2026年04月22日"
            const expiryMatch = body.match(/有效期截止至\\s*(\\d{4}年\\d{1,2}月\\d{1,2}日)/);
            const expiry = expiryMatch ? expiryMatch[1] : null;

            // Extract 5-hour usage: "剩余 100%" or "剩余 85%"
            // Page structure: "5小时用量" followed by "剩余 XX%"
            const fiveHourPct = pct(body.match(/5\\s*小时用量[\\s\\S]*?剩余\\s*(\\d+(?:\\.\\d+)?)\\s*%/));

            // Extract 5-hour reset time
            const fiveHourResetMatch = body.match(/5\\s*小时用量[\\s\\S]*?重置时间[:：]?\\s*([\\d-]+\\s+[\\d:]+)/);
            const fiveHourReset = fiveHourResetMatch ? fiveHourResetMatch[1] : null;

            // Extract weekly usage: "每周用量" followed by "剩余 XX%"
            const weeklyPct = pct(body.match(/每\\s*周用量[\\s\\S]*?剩余\\s*(\\d+(?:\\.\\d+)?)\\s*%/));

            // Extract weekly reset time
            const weeklyResetMatch = body.match(/每\\s*周用量[\\s\\S]*?重置时间[:：]?\\s*([\\d-]+\\s+[\\d:]+)/);
            const weeklyReset = weeklyResetMatch ? weeklyResetMatch[1] : null;

            const hasData = plan || fiveHourPct !== null || weeklyPct !== null;

            return JSON.stringify({
                isLogin: false,
                body: body.substring(0, 1500),
                plan: plan,
                expiry: expiry,
                fiveHourPct: fiveHourPct,
                fiveHourReset: fiveHourReset,
                weeklyPct: weeklyPct,
                weeklyReset: weeklyReset,
                hasData: hasData,
                href: href
            });
        })();
        """

        guard let resultStr = try await webView.evaluateJavaScript(js) as? String,
              let data = resultStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ScrapeResult(isLoginPage: false, bodyText: "", snapshot: nil)
        }

        let isLogin = (dict["isLogin"] as? Bool) ?? false
        let bodyText = (dict["body"] as? String) ?? ""

        if isLogin {
            return ScrapeResult(isLoginPage: true, bodyText: bodyText, snapshot: nil)
        }

        let hasData = (dict["hasData"] as? Bool) ?? false
        guard hasData else {
            return ScrapeResult(isLoginPage: false, bodyText: bodyText, snapshot: nil)
        }

        let snapshot = DashboardSnapshot(
            planName: dict["plan"] as? String,
            planExpiry: dict["expiry"] as? String,
            fiveHourLeftPercent: (dict["fiveHourPct"] as? Int).map { Double($0) },
            fiveHourResetTime: dict["fiveHourReset"] as? String,
            weeklyLeftPercent: (dict["weeklyPct"] as? Int).map { Double($0) },
            weeklyResetTime: dict["weeklyReset"] as? String)

        return ScrapeResult(isLoginPage: false, bodyText: bodyText, snapshot: snapshot)
    }

    /// Bridge for calling from non-MainActor contexts (e.g. ProviderFetchStrategy).
    public nonisolated static func fetchFromMainActor(
        timeout: TimeInterval = 30) async throws -> DashboardSnapshot
    {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                do {
                    let fetcher = StepFunDashboardFetcher()
                    let snapshot = try await fetcher.fetchDashboard(timeout: timeout)
                    continuation.resume(returning: snapshot)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
