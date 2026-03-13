import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TraeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.traeWeb)
    private static let checkLoginURL =
        URL(string: "https://ug-normal.us.trae.ai/cloudide/api/v3/trae/CheckLogin")!
    private static let userInfoURL =
        URL(string: "https://ug-normal.us.trae.ai/cloudide/api/v3/trae/GetUserInfo")!

    public static func fetchUsage(session: TraeSessionInfo, now: Date = Date()) async throws -> TraeUsageSnapshot {
        // Step 1: Check login status and get region info
        let loginResult = try await self.checkLogin(session: session)
        guard loginResult.isLogin else {
            throw TraeAPIError.invalidSession
        }

        Self.log.debug("Trae login valid: userID=\(loginResult.userID ?? "?") region=\(loginResult.region ?? "?")")

        // Step 2: Fetch user info from the correct regional host
        let userInfoHost = loginResult.host ?? "ug-normal.us.trae.ai"
        let userInfoURL = URL(string: "https://\(userInfoHost)/cloudide/api/v3/trae/GetUserInfo")
            ?? self.userInfoURL

        let userInfo = try await self.getUserInfo(url: userInfoURL, session: session)
        return TraeUsageSnapshot(checkLogin: loginResult, userInfo: userInfo, updatedAt: now)
    }

    // MARK: - CheckLogin

    private static func checkLogin(session: TraeSessionInfo) async throws -> TraeCheckLoginResult {
        var request = self.makeRequest(url: self.checkLoginURL, session: session)
        request.httpBody = "{}".data(using: .utf8)

        // Debug: log cookie names being sent (not values for security)
        let cookieNames = session.cookieHeader.split(separator: ";").compactMap { part -> String? in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            return trimmed.split(separator: "=").first.map(String.init)
        }
        Self.log.debug("Trae CheckLogin sending \(cookieNames.count) cookies: \(cookieNames.joined(separator: ", "))")
        Self.log.debug("Trae Cookie header length: \(session.cookieHeader.count) chars")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraeAPIError.networkError("Invalid response")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<binary>"
        Self.log.debug("Trae CheckLogin response (\(httpResponse.statusCode)): \(responseBody)")

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

    // MARK: - GetUserInfo

    private static func getUserInfo(url: URL, session: TraeSessionInfo) async throws -> TraeUserInfoResult {
        var request = self.makeRequest(url: url, session: session)
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraeAPIError.networkError("Invalid response")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<binary>"
        Self.log.debug("Trae GetUserInfo response (\(httpResponse.statusCode)): \(responseBody)")

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw TraeAPIError.invalidSession
            }
            throw TraeAPIError.apiError("GetUserInfo HTTP \(httpResponse.statusCode)")
        }

        // Try structured decode; if it fails, try to extract minimal info from raw JSON
        do {
            let volcResponse = try JSONDecoder().decode(TraeVolcResponse<TraeUserInfoResult>.self, from: data)
            if let error = volcResponse.responseMetadata.error {
                throw TraeAPIError.apiError("GetUserInfo: \(error.message ?? error.code)")
            }
            return volcResponse.result ?? TraeUserInfoResult()
        } catch let error as TraeAPIError {
            throw error
        } catch {
            Self.log.warning("GetUserInfo decode failed: \(error). Response: \(responseBody.prefix(500))")
            // Return empty result — we still have CheckLogin data
            return TraeUserInfoResult()
        }
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
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
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

// MARK: - GetUserInfo Result

/// The actual fields in GetUserInfo are unknown until we see a successful response.
/// This struct is designed to be resilient — all fields optional, decoded flexibly.
struct TraeUserInfoResult: Codable, Sendable {
    let userName: String?
    let email: String?
    let avatarURL: String?
    let plan: String?
    let planExpireTime: String?
    let usage: TraeUsageDetail?
    let quota: TraeQuotaDetail?

    init(userName: String? = nil, email: String? = nil, avatarURL: String? = nil,
         plan: String? = nil, planExpireTime: String? = nil,
         usage: TraeUsageDetail? = nil, quota: TraeQuotaDetail? = nil)
    {
        self.userName = userName
        self.email = email
        self.avatarURL = avatarURL
        self.plan = plan
        self.planExpireTime = planExpireTime
        self.usage = usage
        self.quota = quota
    }

    enum CodingKeys: String, CodingKey {
        case userName = "UserName"
        case email = "Email"
        case avatarURL = "AvatarUrl"
        case plan = "Plan"
        case planExpireTime = "PlanExpireTime"
        case usage = "Usage"
        case quota = "Quota"
    }

    /// Flexible decoder: ignores unknown keys and missing keys.
    init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        self.userName = try? container?.decodeIfPresent(String.self, forKey: .userName)
        self.email = try? container?.decodeIfPresent(String.self, forKey: .email)
        self.avatarURL = try? container?.decodeIfPresent(String.self, forKey: .avatarURL)
        self.plan = try? container?.decodeIfPresent(String.self, forKey: .plan)
        self.planExpireTime = try? container?.decodeIfPresent(String.self, forKey: .planExpireTime)
        self.usage = try? container?.decodeIfPresent(TraeUsageDetail.self, forKey: .usage)
        self.quota = try? container?.decodeIfPresent(TraeQuotaDetail.self, forKey: .quota)
    }
}

struct TraeUsageDetail: Codable, Sendable {
    let used: Int?
    let total: Int?
    let remaining: Int?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case used = "Used"
        case total = "Total"
        case remaining = "Remaining"
        case resetTime = "ResetTime"
    }
}

struct TraeQuotaDetail: Codable, Sendable {
    let used: Int?
    let total: Int?
    let remaining: Int?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case used = "Used"
        case total = "Total"
        case remaining = "Remaining"
        case resetTime = "ResetTime"
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
