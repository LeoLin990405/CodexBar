import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct TraeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.traeWeb)
    private static let userInfoURL =
        URL(string: "https://ug-normal.us.trae.ai/cloudide/api/v3/trae/GetUserInfo")!

    public static func fetchUsage(session: TraeSessionInfo, now: Date = Date()) async throws -> TraeUsageSnapshot {
        var request = URLRequest(url: self.userInfoURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://www.trae.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://www.trae.ai/account-setting", forHTTPHeaderField: "Referer")
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        // Add CSRF token if available
        if let csrfToken = session.csrfToken {
            request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        }
        if let cloudideSession = session.cloudideSession {
            request.setValue(cloudideSession, forHTTPHeaderField: "X-Cloudide-Session")
        }

        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TraeAPIError.networkError("Invalid response")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "<binary data>"
        Self.log.debug("Trae GetUserInfo response (\(httpResponse.statusCode)): \(responseBody)")

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw TraeAPIError.invalidSession
            }
            throw TraeAPIError.apiError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        // Parse the response — try structured decode first, fall back to raw JSON
        do {
            let userInfoResponse = try JSONDecoder().decode(TraeUserInfoResponse.self, from: data)

            guard userInfoResponse.code == 0 else {
                throw TraeAPIError.apiError("API error code \(userInfoResponse.code): \(userInfoResponse.msg ?? "")")
            }

            return TraeUsageSnapshot(userInfo: userInfoResponse, updatedAt: now)
        } catch let decodingError as DecodingError {
            // If structured decode fails, try to extract what we can from raw JSON
            Self.log.warning("Structured decode failed: \(decodingError). Trying raw JSON parse.")
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw TraeAPIError.parseFailed("Response is not valid JSON: \(responseBody.prefix(500))")
            }

            // Build a minimal response from whatever fields exist
            let code = json["code"] as? Int ?? json["status_code"] as? Int ?? 0
            let msg = json["msg"] as? String ?? json["message"] as? String
            let dataObj = json["data"] as? [String: Any]

            let response = TraeUserInfoResponse(
                code: code,
                msg: msg,
                data: dataObj != nil ? TraeUserInfoData(
                    userID: dataObj?["user_id"] as? String ?? dataObj?["userId"] as? String,
                    name: dataObj?["name"] as? String ?? dataObj?["userName"] as? String,
                    email: dataObj?["email"] as? String,
                    avatar: dataObj?["avatar"] as? String,
                    plan: nil,
                    usage: nil,
                    quota: nil) : nil)

            guard code == 0 else {
                throw TraeAPIError.apiError("API error code \(code): \(msg ?? responseBody.prefix(200).description)")
            }

            return TraeUsageSnapshot(userInfo: response, updatedAt: now)
        }
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

// MARK: - API Response Models

struct TraeUserInfoResponse: Codable, Sendable {
    let code: Int
    let msg: String?
    let data: TraeUserInfoData?

    init(code: Int, msg: String?, data: TraeUserInfoData?) {
        self.code = code
        self.msg = msg
        self.data = data
    }
}

struct TraeUserInfoData: Codable, Sendable {
    let userID: String?
    let name: String?
    let email: String?
    let avatar: String?
    let plan: TraePlanInfo?
    let usage: TraeUsageInfo?
    let quota: TraeQuotaInfo?

    init(userID: String?, name: String?, email: String?, avatar: String?,
         plan: TraePlanInfo?, usage: TraeUsageInfo?, quota: TraeQuotaInfo?)
    {
        self.userID = userID
        self.name = name
        self.email = email
        self.avatar = avatar
        self.plan = plan
        self.usage = usage
        self.quota = quota
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case name
        case email
        case avatar
        case plan
        case usage
        case quota
    }
}

struct TraePlanInfo: Codable, Sendable {
    let type: String?
    let name: String?
    let expireTime: String?

    enum CodingKeys: String, CodingKey {
        case type
        case name
        case expireTime = "expire_time"
    }
}

struct TraeUsageInfo: Codable, Sendable {
    let used: Int?
    let total: Int?
    let remaining: Int?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case used
        case total
        case remaining
        case resetTime = "reset_time"
    }
}

struct TraeQuotaInfo: Codable, Sendable {
    let used: Int?
    let total: Int?
    let remaining: Int?
    let resetTime: String?

    enum CodingKeys: String, CodingKey {
        case used
        case total
        case remaining
        case resetTime = "reset_time"
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
