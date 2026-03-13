import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TraeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.traeWeb)
    /// Global endpoint — routes to the correct region automatically.
    /// Do NOT use ug-normal.us.trae.ai; it rejects non-US sessions.
    private static let globalBase = "https://ug-normal.trae.ai"

    private static func apiURL(_ base: String, path: String) -> URL {
        URL(string: "\(base)/\(path)")!
    }

    private static func apiURL(_ base: URL, path: String) -> URL {
        URL(string: "\(base.absoluteString)/\(path)")!
    }

    public static func fetchUsage(session: TraeSessionInfo, now: Date = Date()) async throws -> TraeUsageSnapshot {
        // Step 1: Check login status and get region info
        let loginResult = try await self.checkLogin(session: session)
        guard loginResult.isLogin else {
            throw TraeAPIError.invalidSession
        }

        Self.log.debug("Trae login valid: userID=\(loginResult.userID ?? "?") region=\(loginResult.region ?? "?")")

        // Determine the regional host for subsequent API calls
        let regionalBase: URL
        if let host = loginResult.host, let url = URL(string: host) {
            regionalBase = url
        } else {
            regionalBase = URL(string: self.globalBase)!
        }

        // Step 2: Fetch user profile and usage stats in parallel
        async let profileResult = self.getUserInfo(base: regionalBase, session: session)
        async let statsResult = self.getUserStats(base: regionalBase, session: session)

        let profile = try await profileResult
        let stats = try? await statsResult // stats failure is non-fatal

        return TraeUsageSnapshot(
            checkLogin: loginResult, profile: profile, stats: stats, updatedAt: now)
    }

    // MARK: - CheckLogin

    private static func checkLogin(session: TraeSessionInfo) async throws -> TraeCheckLoginResult {
        let url = self.apiURL(self.globalBase, path: "cloudide/api/v3/trae/CheckLogin")
        var request = self.makeRequest(url: url, session: session)
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraeAPIError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw TraeAPIError.invalidSession
            }
            throw TraeAPIError.apiError("CheckLogin HTTP \(httpResponse.statusCode)")
        }

        let volcResponse = try JSONDecoder().decode(TraeVolcResponse<TraeCheckLoginResult>.self, from: data)
        if let error = volcResponse.responseMetadata.error {
            throw TraeAPIError.apiError("CheckLogin: \(error.message ?? error.code)")
        }
        guard let result = volcResponse.result else {
            throw TraeAPIError.parseFailed("CheckLogin returned no Result")
        }
        return result
    }

    // MARK: - GetUserInfo (profile data)

    private static func getUserInfo(
        base: URL, session: TraeSessionInfo
    ) async throws -> TraeProfileResult {
        let url = self.apiURL(base, path: "cloudide/api/v3/trae/GetUserInfo")
        var request = self.makeRequest(url: url, session: session)
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return TraeProfileResult()
        }

        do {
            let volcResponse = try JSONDecoder().decode(
                TraeVolcResponse<TraeProfileResult>.self, from: data)
            if volcResponse.responseMetadata.error != nil { return TraeProfileResult() }
            return volcResponse.result ?? TraeProfileResult()
        } catch {
            Self.log.warning("GetUserInfo decode failed: \(error)")
            return TraeProfileResult()
        }
    }

    // MARK: - GetUserStasticData (usage statistics)

    private static func getUserStats(
        base: URL, session: TraeSessionInfo
    ) async throws -> TraeStatsResult {
        let url = self.apiURL(base, path: "cloudide/api/v3/trae/GetUserStasticData")
        var request = self.makeRequest(url: url, session: session)

        // API requires LocalTime (ISO 8601 with offset) and Offset (timezone minutes)
        let now = Date()
        let tz = TimeZone.current
        let offsetMinutes = tz.secondsFromGMT(for: now) / 60
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = tz
        let localTime = formatter.string(from: now)

        let body: [String: Any] = ["LocalTime": localTime, "Offset": offsetMinutes]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TraeAPIError.apiError("GetUserStasticData HTTP error")
        }

        let volcResponse = try JSONDecoder().decode(
            TraeVolcResponse<TraeStatsResult>.self, from: data)
        if let error = volcResponse.responseMetadata.error {
            throw TraeAPIError.apiError("Stats: \(error.message ?? error.code)")
        }
        guard let result = volcResponse.result else {
            throw TraeAPIError.parseFailed("GetUserStasticData returned no Result")
        }
        return result
    }

    // MARK: - Request Builder

    private static func makeRequest(url: URL, session: TraeSessionInfo) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.trae.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://www.trae.ai/account-setting", forHTTPHeaderField: "Referer")
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        if let csrfToken = session.csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        }
        if let cloudideSession = session.cloudideSession {
            request.setValue(cloudideSession, forHTTPHeaderField: "X-Cloudide-Session")
        }
        return request
    }
}

// MARK: - Session Info (abstraction over cookie source)

public struct TraeSessionInfo: Sendable {
    public let cookieHeader: String
    public let csrfToken: String?
    public let cloudideSession: String?
    public let sourceLabel: String

    public init(cookieHeader: String, csrfToken: String?, cloudideSession: String?, sourceLabel: String) {
        self.cookieHeader = cookieHeader
        self.csrfToken = csrfToken
        self.cloudideSession = cloudideSession
        self.sourceLabel = sourceLabel
    }

    #if os(macOS)
    public init(from cookieSession: TraeCookieImporter.SessionInfo) {
        self.cookieHeader = cookieSession.cookieHeader
        self.csrfToken = cookieSession.csrfToken
        self.cloudideSession = cookieSession.cloudideSession
        self.sourceLabel = cookieSession.sourceLabel
    }
    #endif
}

// MARK: - ByteDance Volc API Response Format

/// Generic ByteDance Volc Engine API response wrapper.
struct TraeVolcResponse<T: Codable & Sendable>: Codable, Sendable {
    let responseMetadata: TraeVolcResponseMetadata
    let result: T?

    enum CodingKeys: String, CodingKey {
        case responseMetadata = "ResponseMetadata"
        case result = "Result"
    }
}

struct TraeVolcResponseMetadata: Codable, Sendable {
    let requestId: String?
    let action: String?
    let version: String?
    let service: String?
    let region: String?
    let error: TraeVolcError?

    enum CodingKeys: String, CodingKey {
        case requestId = "RequestId"
        case action = "Action"
        case version = "Version"
        case service = "Service"
        case region = "Region"
        case error = "Error"
    }
}

struct TraeVolcError: Codable, Sendable {
    let code: String
    let standardCode: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case standardCode = "StandardCode"
        case message = "Message"
    }
}

// MARK: - CheckLogin Result

struct TraeCheckLoginResult: Codable, Sendable {
    let isLogin: Bool
    let expiredAt: Int?
    let region: String?
    let host: String?
    let userID: String?
    let aiRegion: String?
    let aiHost: String?
    let aiPayHost: String?
    let nickNameEditStatus: String?
    let passwordChanged: Bool?

    init(isLogin: Bool = false, expiredAt: Int? = nil, region: String? = nil,
         host: String? = nil, userID: String? = nil, aiRegion: String? = nil,
         aiHost: String? = nil, aiPayHost: String? = nil,
         nickNameEditStatus: String? = nil, passwordChanged: Bool? = nil)
    {
        self.isLogin = isLogin
        self.expiredAt = expiredAt
        self.region = region
        self.host = host
        self.userID = userID
        self.aiRegion = aiRegion
        self.aiHost = aiHost
        self.aiPayHost = aiPayHost
        self.nickNameEditStatus = nickNameEditStatus
        self.passwordChanged = passwordChanged
    }

    enum CodingKeys: String, CodingKey {
        case isLogin = "IsLogin"
        case expiredAt = "ExpiredAt"
        case region = "Region"
        case host = "Host"
        case userID = "UserID"
        case aiRegion = "AIRegion"
        case aiHost = "AIHost"
        case aiPayHost = "AIPayHost"
        case nickNameEditStatus = "NickNameEditStatus"
        case passwordChanged = "PasswordChanged"
    }
}

// MARK: - GetUserInfo Result (profile data)

struct TraeProfileResult: Codable, Sendable {
    let screenName: String?
    let userID: String?
    let avatarURL: String?
    let region: String?
    let aiRegion: String?
    let registerTime: String?
    let lastLoginTime: String?
    let lastLoginType: String?

    init(screenName: String? = nil, userID: String? = nil, avatarURL: String? = nil,
         region: String? = nil, aiRegion: String? = nil, registerTime: String? = nil,
         lastLoginTime: String? = nil, lastLoginType: String? = nil)
    {
        self.screenName = screenName
        self.userID = userID
        self.avatarURL = avatarURL
        self.region = region
        self.aiRegion = aiRegion
        self.registerTime = registerTime
        self.lastLoginTime = lastLoginTime
        self.lastLoginType = lastLoginType
    }

    enum CodingKeys: String, CodingKey {
        case screenName = "ScreenName"
        case userID = "UserID"
        case avatarURL = "AvatarUrl"
        case region = "Region"
        case aiRegion = "AIRegion"
        case registerTime = "RegisterTime"
        case lastLoginTime = "LastLoginTime"
        case lastLoginType = "LastLoginType"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self.screenName = try? container?.decodeIfPresent(String.self, forKey: .screenName)
        self.userID = try? container?.decodeIfPresent(String.self, forKey: .userID)
        self.avatarURL = try? container?.decodeIfPresent(String.self, forKey: .avatarURL)
        self.region = try? container?.decodeIfPresent(String.self, forKey: .region)
        self.aiRegion = try? container?.decodeIfPresent(String.self, forKey: .aiRegion)
        self.registerTime = try? container?.decodeIfPresent(String.self, forKey: .registerTime)
        self.lastLoginTime = try? container?.decodeIfPresent(String.self, forKey: .lastLoginTime)
        self.lastLoginType = try? container?.decodeIfPresent(String.self, forKey: .lastLoginType)
    }
}

// MARK: - GetUserStasticData Result (usage statistics)

struct TraeStatsResult: Codable, Sendable {
    let userID: String?
    let registerDays: Int?
    /// AI interaction counts per day (key: "yyyyMMdd", value: count)
    let aiCnt365d: [String: Int]?
    let codeAiAcceptCnt7d: Int?
    /// Accepted AI suggestions by language (key: language, value: count)
    let codeAiAcceptDiffLanguageCnt7d: [String: Int]?
    let codeCompCnt7d: Int?
    /// Completions by agent (key: agent name, value: count)
    let codeCompDiffAgentCnt7d: [String: Int]?
    /// Completions by model (key: model name, value: count)
    let codeCompDiffModelCnt7d: [String: Int]?
    let dataDate: String?
    let isIde: Bool?

    enum CodingKeys: String, CodingKey {
        case userID = "UserID"
        case registerDays = "RegisterDays"
        case aiCnt365d = "AiCnt365d"
        case codeAiAcceptCnt7d = "CodeAiAcceptCnt7d"
        case codeAiAcceptDiffLanguageCnt7d = "CodeAiAcceptDiffLanguageCnt7d"
        case codeCompCnt7d = "CodeCompCnt7d"
        case codeCompDiffAgentCnt7d = "CodeCompDiffAgentCnt7d"
        case codeCompDiffModelCnt7d = "CodeCompDiffModelCnt7d"
        case dataDate = "DataDate"
        case isIde = "IsIde"
    }

    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self.userID = try? container?.decodeIfPresent(String.self, forKey: .userID)
        self.registerDays = try? container?.decodeIfPresent(Int.self, forKey: .registerDays)
        self.aiCnt365d = try? container?.decodeIfPresent([String: Int].self, forKey: .aiCnt365d)
        self.codeAiAcceptCnt7d = try? container?.decodeIfPresent(Int.self, forKey: .codeAiAcceptCnt7d)
        self.codeAiAcceptDiffLanguageCnt7d = try? container?.decodeIfPresent(
            [String: Int].self, forKey: .codeAiAcceptDiffLanguageCnt7d)
        self.codeCompCnt7d = try? container?.decodeIfPresent(Int.self, forKey: .codeCompCnt7d)
        self.codeCompDiffAgentCnt7d = try? container?.decodeIfPresent(
            [String: Int].self, forKey: .codeCompDiffAgentCnt7d)
        self.codeCompDiffModelCnt7d = try? container?.decodeIfPresent(
            [String: Int].self, forKey: .codeCompDiffModelCnt7d)
        self.dataDate = try? container?.decodeIfPresent(String.self, forKey: .dataDate)
        self.isIde = try? container?.decodeIfPresent(Bool.self, forKey: .isIde)
    }
}

// MARK: - Errors

public enum TraeAPIError: LocalizedError, Sendable {
    case invalidSession
    case networkError(String)
    case parseFailed(String)
    case apiError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidSession:
            "Trae session expired. Please log in to trae.ai in your browser."
        case .networkError(let msg):
            "Trae network error: \(msg)"
        case .parseFailed(let msg):
            "Trae response parse failed: \(msg)"
        case .apiError(let msg):
            "Trae API error: \(msg)"
        }
    }
}
