import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum MiMoSettingsError: LocalizedError, Equatable, Sendable {
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
            "Xiaomi MiMo API key not found. Set apiKey in ~/.codexbar/config.json or MIMO_API_KEY."
        case let .invalidAPIKey(region):
            "Invalid Xiaomi MiMo API key for \(region). Check apiKey and region in ~/.codexbar/config.json."
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
    public static let apiURLKey = "MIMO_API_URL"
    public static let apiBaseURLKey = "MIMO_API_BASE_URL"
    public static let apiRegionKey = "MIMO_REGION"
    public static let tokenPlanRegions = ["cn", "sgp", "ams"]
    public static let apiKeyEnvironmentKeys = [
        "MIMO_API_KEY",
        "XIAOMI_API_KEY",
    ]

    public static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for key in self.apiKeyEnvironmentKeys {
            if let token = self.cleaned(environment[key]) { return token }
        }
        return nil
    }

    public static func apiURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment[self.apiURLKey],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme, !scheme.isEmpty
        {
            return url
        }
        return URL(string: "https://platform.xiaomimimo.com/api/v1")!
    }

    public static func apiBaseURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        self.apiBaseURLs(environment: environment).first?.url ?? URL(string: "https://api.xiaomimimo.com/v1")!
    }

    public static func apiBaseURLs(
        environment: [String: String] = ProcessInfo.processInfo.environment) -> [(label: String, url: URL)]
    {
        if let override = environment[self.apiBaseURLKey],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           let scheme = url.scheme, !scheme.isEmpty
        {
            return [(label: "configured endpoint", url: url)]
        }

        let region = self.cleaned(environment[self.apiRegionKey])?.lowercased()
        let orderedRegions: [String] = if let region, self.tokenPlanRegions.contains(region) {
            [region] + self.tokenPlanRegions.filter { $0 != region }
        } else {
            self.tokenPlanRegions
        }

        var endpoints = orderedRegions.map { region in
            (
                label: region,
                url: self.tokenPlanAPIBaseURL(region: region))
        }
        endpoints.append((
            label: "global",
            url: self.globalAPIBaseURL))
        return endpoints
    }

    private static var globalAPIBaseURL: URL {
        URL(string: "https://api.xiaomimimo.com/v1")!
    }

    private static func tokenPlanAPIBaseURL(region: String) -> URL {
        URL(string: "https://token-plan-\(region).xiaomimimo.com/anthropic")!
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

public enum MiMoUsageFetcher {
    private static let requestTimeout: TimeInterval = 15

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

    public static func fetchAPIUsage(
        apiKey: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date()) async throws -> UsageSnapshot
    {
        let cleanedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedKey.isEmpty else {
            throw MiMoSettingsError.missingAPIKey
        }

        var invalidEndpoints: [String] = []
        var lastError: Error?

        for endpoint in MiMoSettingsReader.apiBaseURLs(environment: environment) {
            do {
                let request = try self.makeAPIValidationRequest(baseURL: endpoint.url, apiKey: cleanedKey)
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MiMoUsageError.networkError("Invalid response")
                }
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    invalidEndpoints.append(endpoint.label)
                    continue
                }
                switch httpResponse.statusCode {
                case 200...299, 400, 422, 429:
                    return self.makeAPIUsageSnapshot(from: data, now: now)
                default:
                    throw MiMoUsageError.networkError("HTTP \(httpResponse.statusCode)")
                }
            } catch {
                lastError = error
                continue
            }
        }

        if !invalidEndpoints.isEmpty {
            throw MiMoSettingsError.invalidAPIKey(invalidEndpoints.joined(separator: ", "))
        }
        if let lastError { throw lastError }
        throw MiMoSettingsError.invalidAPIKey("configured endpoint")
    }

    private static func makeAPIUsageSnapshot(from data: Data, now: Date) -> UsageSnapshot {
        let apiResponse = try? JSONDecoder().decode(APIUsageResponse.self, from: data)
        let detail: String?
        if let usage = apiResponse?.usage {
            let total = usage.totalTokens ?? 0
            detail = total > 0 ? "Validation used \(total.formatted()) tokens" : nil
        } else {
            detail = nil
        }

        let primary = RateWindow(
            usedPercent: 0,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: detail ?? "API key active")
        let identity = ProviderIdentitySnapshot(
            providerID: .mimo,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: "Token Plan")
        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            updatedAt: now,
            identity: identity)
    }

    private static func makeAPIValidationRequest(baseURL: URL, apiKey: String) throws -> URLRequest {
        if self.usesAnthropicMessagesAPI(baseURL: baseURL) {
            var request = URLRequest(url: baseURL.appendingPathComponent("v1").appendingPathComponent("messages"))
            request.httpMethod = "POST"
            request.timeoutInterval = Self.requestTimeout
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "model": "mimo-v2.5",
                "messages": [
                    ["role": "user", "content": "hi"],
                ],
                "max_tokens": 1,
            ])
            return request
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat").appendingPathComponent("completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "mimo-v2.5",
            "messages": [
                ["role": "user", "content": "hi"],
            ],
            "max_tokens": 1,
        ])
        return request
    }

    private static func usesAnthropicMessagesAPI(baseURL: URL) -> Bool {
        if baseURL.pathComponents.contains("anthropic") {
            return true
        }
        return baseURL.host?.hasPrefix("token-plan-") == true
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

    private struct APIUsageResponse: Decodable {
        let usage: APIUsage?
    }

    private struct APIUsage: Decodable {
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens
            case totalTokensSnake = "total_tokens"
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let total = try container.decodeIfPresent(Int.self, forKey: .totalTokens) ??
                container.decodeIfPresent(Int.self, forKey: .totalTokensSnake)
            {
                self.totalTokens = total
                return
            }
            let input = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            let output = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
            let total = input + output
            self.totalTokens = total > 0 ? total : nil
        }
    }
}
