#if os(macOS)
import Foundation
import WebKit

/// Scrapes the AigoCode dashboard to extract usage data.
///
/// AigoCode uses Supabase + Next.js with server-side rendering. The usage data is only
/// available by rendering the full dashboard page, so we use an offscreen WKWebView
/// to load the page and extract values from the DOM via JavaScript.
@MainActor
public struct AigoCodeDashboardFetcher {
    public enum FetchError: LocalizedError {
        case loginRequired
        case noUsageData(body: String)
        case timeout

        public var errorDescription: String? {
            switch self {
            case .loginRequired:
                "AigoCode web access requires login. Open Settings → AigoCode → Login in Browser."
            case let .noUsageData(body):
                "AigoCode dashboard data not found. Body sample: \(body.prefix(200))"
            case .timeout:
                "AigoCode dashboard loading timed out."
            }
        }
    }

    private static let log = CodexBarLog.logger(LogCategories.aigocodeWeb)
    private static let dashboardURL = URL(string: "https://www.aigocode.com/dashboard/console")!

    public init() {}

    // MARK: - Public

    public func fetchDashboard(
        websiteDataStore: WKWebsiteDataStore = .default(),
        supabaseTokenJSON: String? = nil,
        timeout: TimeInterval = 45) async throws -> AigoCodeDashboardSnapshot
    {
        let deadline = Date().addingTimeInterval(max(1, timeout))

        let config = WKWebViewConfiguration()
        config.websiteDataStore = websiteDataStore
        let webView = WKWebView(frame: CGRect(x: -9999, y: -9999, width: 1200, height: 900), configuration: config)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"

        defer {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }

        // If we have a Supabase token from Chrome, inject it into localStorage first.
        // We load a blank page on the AigoCode origin, set the token, then navigate.
        if let supabaseTokenJSON {
            Self.log.debug("Injecting Supabase session into localStorage")
            _ = webView.load(URLRequest(url: URL(string: "https://www.aigocode.com/favicon.ico")!))
            try? await Task.sleep(for: .milliseconds(2000))

            let escaped = supabaseTokenJSON
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let injectJS = "localStorage.setItem('\(AigoCodeLocalStorageImporter.supabaseTokenKey)', '\(escaped)'); 'ok';"
            let result = try? await webView.evaluateJavaScript(injectJS)
            Self.log.debug("localStorage injection result: \(String(describing: result))")
        }

        _ = webView.load(URLRequest(url: Self.dashboardURL))
        Self.log.debug("Loading AigoCode dashboard…")

        // Poll until we find usage data or hit the deadline
        var lastBody: String = ""
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(1500))

            let scrape = try await self.scrape(webView: webView)

            // Detect login page
            if scrape.isLoginPage {
                Self.log.debug("Login page detected")
                throw FetchError.loginRequired
            }

            lastBody = scrape.bodyText

            // Check if we have subscription usage data
            if let snapshot = scrape.snapshot {
                Self.log.debug(
                    "Dashboard parsed: subscription=\(snapshot.subscriptionUsedDollars)/\(snapshot.subscriptionTotalDollars) " +
                    "weekly=\(snapshot.weeklyUsedDollars)/\(snapshot.weeklyTotalDollars)")
                return snapshot
            }
        }

        throw FetchError.noUsageData(body: lastBody)
    }

    // MARK: - JavaScript Scraping

    private struct ScrapeResult {
        let isLoginPage: Bool
        let bodyText: String
        let snapshot: AigoCodeDashboardSnapshot?
    }

    private func scrape(webView: WKWebView) async throws -> ScrapeResult {
        let js = """
        (() => {
            const href = window.location.href;
            const body = document.body ? document.body.innerText : '';

            // Detect login page
            const isLogin = href.includes('/auth/login') ||
                body.includes('欢迎回来') && body.includes('使用 Google 登录');

            if (isLogin) {
                return JSON.stringify({ isLogin: true, body: body.substring(0, 500) });
            }

            // Extract usage data from the console/stats page
            // Pattern: "已用 $X / 共 $Y" or "已用 $X / $Y"
            const usagePattern = /已用\\s*\\$([\\d,.]+)\\s*\\/\\s*共?\\s*\\$([\\d,.]+)/g;
            const usages = [];
            let match;
            while ((match = usagePattern.exec(body)) !== null) {
                usages.push({ used: match[1].replace(/,/g, ''), total: match[2].replace(/,/g, '') });
            }

            // Extract plan info
            // Pattern: "Professional Plan" or similar, followed by expiration
            const planMatch = body.match(/(\\w+\\s*Plan)[，,]?\\s*到期\\s*([\\d/]+)/);
            const plan = planMatch ? planMatch[1] : null;
            const expiry = planMatch ? planMatch[2] : null;

            // Extract flexible balance
            // Pattern: "<$0.01" or "$1.23"
            const flexMatch = body.match(/灵活余额[\\s\\S]{0,50}?[<>]?\\$([\\d,.]+)/);
            const flexBalance = flexMatch ? flexMatch[1].replace(/,/g, '') : null;

            // Extract weekly reset info
            // Pattern: "X天Y小时后重置" or "X小时后重置"
            const resetMatch = body.match(/(\\d+天)?(\\d+小时)?后重置/);
            const resetText = resetMatch ? resetMatch[0] : null;

            // Extract usage percentage
            const pctPattern = /已使用\\s*(\\d+)%/g;
            const pcts = [];
            let pctMatch;
            while ((pctMatch = pctPattern.exec(body)) !== null) {
                pcts.push(parseInt(pctMatch[1]));
            }

            return JSON.stringify({
                isLogin: false,
                body: body.substring(0, 1000),
                usages: usages,
                plan: plan,
                expiry: expiry,
                flexBalance: flexBalance,
                resetText: resetText,
                pcts: pcts,
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

        guard let usages = dict["usages"] as? [[String: String]], !usages.isEmpty else {
            return ScrapeResult(isLoginPage: false, bodyText: bodyText, snapshot: nil)
        }

        // First usage entry = subscription, second = weekly (if present)
        let subUsed = Double(usages[0]["used"] ?? "0") ?? 0
        let subTotal = Double(usages[0]["total"] ?? "0") ?? 0
        let weekUsed = usages.count > 1 ? (Double(usages[1]["used"] ?? "0") ?? 0) : 0
        let weekTotal = usages.count > 1 ? (Double(usages[1]["total"] ?? "0") ?? 0) : 0

        let plan = dict["plan"] as? String
        let expiry = dict["expiry"] as? String
        let flexBalance = Double((dict["flexBalance"] as? String) ?? "0") ?? 0
        let resetText = dict["resetText"] as? String

        let snapshot = AigoCodeDashboardSnapshot(
            subscriptionUsedDollars: subUsed,
            subscriptionTotalDollars: subTotal,
            weeklyUsedDollars: weekUsed,
            weeklyTotalDollars: weekTotal,
            planName: plan,
            planExpiry: expiry,
            flexibleBalanceDollars: flexBalance,
            weeklyResetText: resetText,
            updatedAt: Date())

        return ScrapeResult(isLoginPage: false, bodyText: bodyText, snapshot: snapshot)
    }
}

// MARK: - Dashboard Snapshot

public struct AigoCodeDashboardSnapshot: Sendable {
    public let subscriptionUsedDollars: Double
    public let subscriptionTotalDollars: Double
    public let weeklyUsedDollars: Double
    public let weeklyTotalDollars: Double
    public let planName: String?
    public let planExpiry: String?
    public let flexibleBalanceDollars: Double
    public let weeklyResetText: String?
    public let updatedAt: Date

    public init(
        subscriptionUsedDollars: Double,
        subscriptionTotalDollars: Double,
        weeklyUsedDollars: Double,
        weeklyTotalDollars: Double,
        planName: String?,
        planExpiry: String?,
        flexibleBalanceDollars: Double,
        weeklyResetText: String?,
        updatedAt: Date)
    {
        self.subscriptionUsedDollars = subscriptionUsedDollars
        self.subscriptionTotalDollars = subscriptionTotalDollars
        self.weeklyUsedDollars = weeklyUsedDollars
        self.weeklyTotalDollars = weeklyTotalDollars
        self.planName = planName
        self.planExpiry = planExpiry
        self.flexibleBalanceDollars = flexibleBalanceDollars
        self.weeklyResetText = weeklyResetText
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let subPercent: Double
        let subDescription: String
        if self.subscriptionTotalDollars > 0 {
            subPercent = min(100, max(0, self.subscriptionUsedDollars / self.subscriptionTotalDollars * 100))
            subDescription = "$\(Self.fmt(self.subscriptionUsedDollars))/$\(Self.fmt(self.subscriptionTotalDollars))"
        } else {
            subPercent = 0
            subDescription = "No subscription data"
        }

        let weekPercent: Double
        let weekDescription: String
        if self.weeklyTotalDollars > 0 {
            weekPercent = min(100, max(0, self.weeklyUsedDollars / self.weeklyTotalDollars * 100))
            var desc = "$\(Self.fmt(self.weeklyUsedDollars))/$\(Self.fmt(self.weeklyTotalDollars))"
            if let reset = self.weeklyResetText {
                desc += " (\(reset))"
            }
            weekDescription = desc
        } else {
            weekPercent = 0
            weekDescription = "No weekly data"
        }

        let primary = RateWindow(
            usedPercent: subPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: subDescription)

        let secondary = RateWindow(
            usedPercent: weekPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: weekDescription)

        var planDescription: String?
        if let plan = self.planName {
            planDescription = plan
            if let expiry = self.planExpiry {
                planDescription! += ", expires \(expiry)"
            }
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .aigocode,
            accountEmail: planDescription,
            accountOrganization: nil,
            loginMethod: "Web")

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private static func fmt(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }
}
#endif
