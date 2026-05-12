import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MiMoSettingsError: LocalizedError, Sendable, Equatable {
    case missingCookie
    case invalidCookie
    case missingAPIKey
    case invalidAPIKey(String)

    public var errorDescription: String? {
        switch self {
        case .missingCookie:
            "No Xiaomi MiMo browser session found. Log in at platform.xiaomimimo.com first."
        case .invalidCookie:
            "Xiaomi MiMo requires the api-platform_serviceToken and userId cookies."
        case .missingAPIKey:
            "Set MIMO_API_KEY (Xiaomi Token Plan key, tp-…) or paste it into ~/.codexbar/config.json."
        case let .invalidAPIKey(endpoints):
            "Xiaomi MiMo API key rejected by all probed endpoints: \(endpoints). " +
                "Verify the key in ~/.codexbar/config.json and the bound region."
        }
    }
}

public enum MiMoUsageError: LocalizedError, Sendable {
    case invalidCredentials
    case loginRequired
    case parseFailed(String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Xiaomi MiMo browser session expired. Log in again."
        case .loginRequired:
            "Xiaomi MiMo login required."
        case let .parseFailed(message):
            "Could not parse Xiaomi MiMo balance: \(message)"
        case let .networkError(message):
            "Xiaomi MiMo request failed: \(message)"
        }
    }
}

public enum MiMoSettingsReader {
    public enum APIAuthStyle: Sendable {
        case bearer
        case xAPIKey
    }

    public static let apiURLKey = "MIMO_API_URL"
    public static let apiBaseURLKey = "MIMO_API_BASE_URL"
    public static let apiRegionKey = "MIMO_REGION"
    public static let apiKeyEnvironmentKeys = [
        "MIMO_API_KEY",
        "XIAOMI_API_KEY",
    ]
    public static let tokenPlanRegions = ["cn", "sgp", "ams"]

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for key in self.apiKeyEnvironmentKeys {
            if let token = self.cleaned(environment[key]) { return token }
        }
        return nil
    }

    /// Cookie-mode dashboard endpoint. Distinct from Token Plan API endpoints.
    public static func apiURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[self.apiURLKey],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme, !scheme.isEmpty
        {
            return url
        }
        return URL(string: "https://platform.xiaomimimo.com/api/v1")!
    }

    /// All (label, base URL, auth style) tuples the API-key strategy should try, in order.
    /// Honors `MIMO_API_BASE_URL` and `MIMO_REGION` overrides; otherwise probes the
    /// three Token Plan regions (cn / sgp / ams) with OpenAI bearer auth, then
    /// falls back to the global pay-per-token endpoint.
    ///
    /// Note: we only probe OpenAI endpoints because Xiaomi's Anthropic-compatible
    /// `/anthropic/v1/models` returns 404 — Anthropic spec exposes `/v1/messages`
    /// for inference but not a free list-models call. Probing it would generate
    /// confusing 404 noise without adding any signal.
    public static func apiBaseURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment)
        -> [(label: String, url: URL, authStyle: APIAuthStyle)]
    {
        if let override = environment[self.apiBaseURLKey],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme, !scheme.isEmpty
        {
            return [(label: "configured", url: url, authStyle: .bearer)]
        }

        let region = self.cleaned(environment[self.apiRegionKey])?.lowercased()
        let ordered: [String] = if let region, self.tokenPlanRegions.contains(region) {
            [region] + self.tokenPlanRegions.filter { $0 != region }
        } else {
            self.tokenPlanRegions
        }

        var endpoints = ordered.map { region in
            (
                label: "token-plan-\(region)",
                url: self.tokenPlanOpenAIBaseURL(region: region),
                authStyle: APIAuthStyle.bearer)
        }
        endpoints.append((label: "global", url: self.globalOpenAIBaseURL, authStyle: .bearer))
        return endpoints
    }

    private static var globalOpenAIBaseURL: URL {
        URL(string: "https://api.xiaomimimo.com/v1")!
    }

    private static var globalAnthropicBaseURL: URL {
        URL(string: "https://api.xiaomimimo.com/anthropic")!
    }

    private static func tokenPlanOpenAIBaseURL(region: String) -> URL {
        URL(string: "https://token-plan-\(region).xiaomimimo.com/v1")!
    }

    private static func tokenPlanAnthropicBaseURL(region: String) -> URL {
        URL(string: "https://token-plan-\(region).xiaomimimo.com/anthropic")!
    }

    private static func cleaned(_ raw: String?) -> String? {
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

public enum MiMoUsageFetcher {
    private static let requestTimeout: TimeInterval = 15

    /// Probes the configured base URLs with the supplied API key and returns a
    /// minimal `UsageSnapshot` describing which endpoint accepted the key.
    /// Uses GET /models (OpenAI) or GET /v1/models (Anthropic) so the probe is
    /// free of LLM token consumption.
    public static func fetchAPIUsage(
        apiKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw MiMoSettingsError.missingAPIKey
        }

        var rejectedEndpoints: [String] = []
        var lastError: Error?

        for endpoint in MiMoSettingsReader.apiBaseURLs(environment: environment) {
            do {
                let request = self.makeListModelsRequest(
                    baseURL: endpoint.url,
                    apiKey: key,
                    authStyle: endpoint.authStyle)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MiMoUsageError.networkError("Invalid response")
                }
                switch httpResponse.statusCode {
                case 200...299:
                    return self.makeAPIUsageSnapshot(
                        endpointLabel: endpoint.label,
                        now: now)
                case 401, 403:
                    rejectedEndpoints.append(endpoint.label)
                    continue
                default:
                    rejectedEndpoints.append("\(endpoint.label) (HTTP \(httpResponse.statusCode))")
                    continue
                }
            } catch {
                lastError = error
                continue
            }
        }

        if !rejectedEndpoints.isEmpty {
            throw MiMoSettingsError.invalidAPIKey(rejectedEndpoints.joined(separator: ", "))
        }
        if let lastError { throw lastError }
        throw MiMoSettingsError.invalidAPIKey("configured endpoint")
    }

    private static func makeListModelsRequest(
        baseURL: URL,
        apiKey: String,
        authStyle: MiMoSettingsReader.APIAuthStyle) -> URLRequest
    {
        let isAnthropic = baseURL.pathComponents.contains("anthropic")
        let url = isAnthropic
            ? baseURL.appendingPathComponent("v1").appendingPathComponent("models")
            : baseURL.appendingPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch authStyle {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .xAPIKey:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        if isAnthropic {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        return request
    }

    private static func makeAPIUsageSnapshot(endpointLabel: String, now: Date) -> UsageSnapshot {
        let primary = RateWindow(
            usedPercent: 0,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: "API key active via \(endpointLabel)")
        let identity = ProviderIdentitySnapshot(
            providerID: .mimo,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Token Plan API")
        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: now,
            identity: identity)
    }

    public static func fetchUsage(
        cookieHeader: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> MiMoUsageSnapshot
    {
        guard let normalizedCookie = MiMoCookieHeader.normalizedHeader(from: cookieHeader) else {
            throw MiMoSettingsError.invalidCookie
        }

        let balanceURL = MiMoSettingsReader.apiURL(environment: environment).appendingPathComponent("balance")
        let tokenDetailURL = MiMoSettingsReader.apiURL(environment: environment)
            .appendingPathComponent("tokenPlan/detail")
        let tokenUsageURL = MiMoSettingsReader.apiURL(environment: environment)
            .appendingPathComponent("tokenPlan/usage")

        async let balanceData = self.fetchAuthenticated(url: balanceURL, cookie: normalizedCookie)
        let tokenDetailData: Data? = try? await self.fetchAuthenticated(url: tokenDetailURL, cookie: normalizedCookie)
        let tokenUsageData: Data? = try? await self.fetchAuthenticated(url: tokenUsageURL, cookie: normalizedCookie)

        return try await self.parseCombinedSnapshot(
            balanceData: balanceData,
            tokenDetailData: tokenDetailData,
            tokenUsageData: tokenUsageData,
            now: now)
    }

    private static func fetchAuthenticated(
        url: URL,
        cookie: String,
        environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> Data
    {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("UTC+01:00", forHTTPHeaderField: "x-timeZone")
        request.setValue("https://platform.xiaomimimo.com", forHTTPHeaderField: "Origin")
        request.setValue("https://platform.xiaomimimo.com/#/console/balance", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MiMoUsageError.networkError("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw MiMoUsageError.loginRequired
        case 403:
            throw MiMoUsageError.invalidCredentials
        default:
            throw MiMoUsageError.networkError("HTTP \(httpResponse.statusCode)")
        }

        return data
    }

    static func parseCombinedSnapshot(
        balanceData: Data,
        tokenDetailData: Data?,
        tokenUsageData: Data?,
        now: Date = Date()) throws -> MiMoUsageSnapshot
    {
        let balanceSnapshot = try self.parseUsageSnapshot(from: balanceData, now: now)
        let planDetail: (planCode: String?, periodEnd: Date?, expired: Bool) = {
            guard let data = tokenDetailData, let result = try? self.parseTokenPlanDetail(from: data) else {
                return (planCode: nil, periodEnd: nil, expired: false)
            }
            return result
        }()
        let planUsage: (used: Int, limit: Int, percent: Double) = {
            guard let data = tokenUsageData, let result = try? self.parseTokenPlanUsage(from: data) else {
                return (used: 0, limit: 0, percent: 0)
            }
            return result
        }()

        return MiMoUsageSnapshot(
            balance: balanceSnapshot.balance,
            currency: balanceSnapshot.currency,
            planCode: planDetail.planCode,
            planPeriodEnd: planDetail.periodEnd,
            planExpired: planDetail.expired,
            tokenUsed: planUsage.used,
            tokenLimit: planUsage.limit,
            tokenPercent: planUsage.percent,
            updatedAt: now)
    }

    static func parseUsageSnapshot(from data: Data, now: Date = Date()) throws -> MiMoUsageSnapshot {
        let decoder = JSONDecoder()
        let response = try decoder.decode(BalanceResponse.self, from: data)

        guard response.code == 0 else {
            let message = response.message?.trimmingCharacters(in: .whitespacesAndNewlines)
            if response.code == 401 {
                throw MiMoUsageError.loginRequired
            }
            if response.code == 403 {
                throw MiMoUsageError.invalidCredentials
            }
            throw MiMoUsageError.parseFailed(message?.isEmpty == false ? message! : "code \(response.code)")
        }

        guard let data = response.data else {
            throw MiMoUsageError.parseFailed("Missing balance payload")
        }
        guard let balance = Double(data.balance) else {
            throw MiMoUsageError.parseFailed("Invalid balance value")
        }

        let currency = data.currency.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currency.isEmpty else {
            throw MiMoUsageError.parseFailed("Missing currency")
        }

        return MiMoUsageSnapshot(balance: balance, currency: currency, updatedAt: now)
    }

    static func parseTokenPlanDetail(from data: Data) throws -> (planCode: String?, periodEnd: Date?, expired: Bool) {
        let decoder = JSONDecoder()
        let response = try decoder.decode(TokenPlanDetailResponse.self, from: data)

        guard response.code == 0, let payload = response.data else {
            return (planCode: nil, periodEnd: nil, expired: false)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let periodEnd: Date? = if let dateStr = payload.currentPeriodEnd {
            formatter.date(from: dateStr)
        } else {
            nil
        }

        return (planCode: payload.planCode, periodEnd: periodEnd, expired: payload.expired)
    }

    static func parseTokenPlanUsage(from data: Data) throws -> (used: Int, limit: Int, percent: Double) {
        let decoder = JSONDecoder()
        let response = try decoder.decode(TokenPlanUsageResponse.self, from: data)

        guard response.code == 0,
              let monthUsage = response.data?.monthUsage,
              let item = monthUsage.items.first
        else {
            return (used: 0, limit: 0, percent: 0)
        }

        return (used: item.used, limit: item.limit, percent: item.percent)
    }

    private struct BalanceResponse: Decodable {
        let code: Int
        let message: String?
        let data: BalancePayload?
    }

    private struct BalancePayload: Decodable {
        let balance: String
        let currency: String
    }

    private struct TokenPlanDetailResponse: Decodable {
        let code: Int
        let message: String?
        let data: TokenPlanDetailPayload?
    }

    private struct TokenPlanDetailPayload: Decodable {
        let planCode: String?
        let currentPeriodEnd: String?
        let expired: Bool
    }

    private struct TokenPlanUsageResponse: Decodable {
        let code: Int
        let message: String?
        let data: TokenPlanUsagePayload?
    }

    private struct TokenPlanUsagePayload: Decodable {
        let monthUsage: MonthUsage?
    }

    private struct MonthUsage: Decodable {
        let percent: Double
        let items: [UsageItem]
    }

    private struct UsageItem: Decodable {
        let name: String
        let used: Int
        let limit: Int
        let percent: Double
    }
}
