import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AigoCodeUsageSnapshot: Sendable {
    public let remainingRequests: Int
    public let limitRequests: Int
    public let resetTime: Date?
    public let updatedAt: Date
    public let apiKeyValid: Bool
    public let totalTokens: Int?

    public init(
        remainingRequests: Int,
        limitRequests: Int,
        resetTime: Date?,
        updatedAt: Date,
        apiKeyValid: Bool = false,
        totalTokens: Int? = nil)
    {
        self.remainingRequests = remainingRequests
        self.limitRequests = limitRequests
        self.resetTime = resetTime
        self.updatedAt = updatedAt
        self.apiKeyValid = apiKeyValid
        self.totalTokens = totalTokens
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let usedPercent: Double
        let resetDescription: String

        if self.limitRequests > 0 {
            let used = max(0, self.limitRequests - self.remainingRequests)
            usedPercent = min(100, max(0, Double(used) / Double(self.limitRequests) * 100))
            resetDescription = "\(used)/\(self.limitRequests) requests"
        } else if self.apiKeyValid {
            usedPercent = 0
            resetDescription = "Active — check dashboard for details"
        } else {
            usedPercent = 0
            resetDescription = "No usage data"
        }

        let primary = RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: self.resetTime,
            resetDescription: resetDescription)

        let identity = ProviderIdentitySnapshot(
            providerID: .aigocode,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}

public enum AigoCodeUsageError: LocalizedError, Sendable {
    case missingCredentials
    case networkError(String)
    case apiError(Int, String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Missing AigoCode API key (AIGOCODE_API_KEY)."
        case let .networkError(message):
            "AigoCode network error: \(message)"
        case let .apiError(code, message):
            "AigoCode API error (\(code)): \(message)"
        case let .parseFailed(message):
            "Failed to parse AigoCode response: \(message)"
        }
    }
}

public struct AigoCodeUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.aigocodeUsage)

    private static let apiURL = URL(string: "https://api.aigocode.com/v1/messages")!

    public static func fetchUsage(apiKey: String) async throws -> AigoCodeUsageSnapshot {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AigoCodeUsageError.missingCredentials
        }

        var request = URLRequest(url: self.apiURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "anthropic/claude-sonnet-4-5",
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "hi"],
            ] as [[String: Any]],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AigoCodeUsageError.networkError("Invalid response")
        }

        // Accept both 200 (success) and 429 (rate limited) – both carry rate limit headers.
        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 429 else {
            let summary = Self.apiErrorSummary(statusCode: httpResponse.statusCode, data: data)
            Self.log.error("AigoCode API returned \(httpResponse.statusCode): \(summary)")
            throw AigoCodeUsageError.apiError(httpResponse.statusCode, summary)
        }

        let headers = httpResponse.allHeaderFields
        let remaining = Self.intHeader(headers, "x-ratelimit-remaining-requests")
        let limit = Self.intHeader(headers, "x-ratelimit-limit-requests")
        let resetString = headers["x-ratelimit-reset-requests"] as? String

        let resetTime: Date? = resetString.flatMap(Self.parseResetTime)

        var totalTokens: Int?
        if remaining == nil, limit == nil,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let usage = json["usage"] as? [String: Any]
        {
            totalTokens = usage["total_tokens"] as? Int
        }

        let snapshot = AigoCodeUsageSnapshot(
            remainingRequests: remaining ?? 0,
            limitRequests: limit ?? 0,
            resetTime: resetTime,
            updatedAt: Date(),
            apiKeyValid: httpResponse.statusCode == 200,
            totalTokens: totalTokens)

        Self.log.debug(
            "AigoCode usage parsed remaining=\(snapshot.remainingRequests) limit=\(snapshot.limitRequests) valid=\(snapshot.apiKeyValid)")

        return snapshot
    }

    private static func intHeader(_ headers: [AnyHashable: Any], _ name: String) -> Int? {
        if let value = headers[name] as? String, let int = Int(value) {
            return int
        }
        if let value = headers[name.lowercased()] as? String, let int = Int(value) {
            return int
        }
        // Case-insensitive search
        for (key, val) in headers {
            if let keyStr = key as? String,
               keyStr.lowercased() == name.lowercased(),
               let valStr = val as? String,
               let int = Int(valStr)
            {
                return int
            }
        }
        return nil
    }

    /// Parse reset time from header value like "1d2h3m4s" or "30s" or ISO 8601.
    private static func parseResetTime(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // Try ISO 8601 first
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: trimmed) { return date }
        let isoFallback = ISO8601DateFormatter()
        isoFallback.formatOptions = [.withInternetDateTime]
        if let date = isoFallback.date(from: trimmed) { return date }

        // Try duration format like "1d2h3m4s" or "30s"
        var seconds: TimeInterval = 0
        let pattern = /(\d+)([dhms])/
        for match in trimmed.matches(of: pattern) {
            guard let num = Double(match.1) else { continue }
            switch match.2 {
            case "d": seconds += num * 86400
            case "h": seconds += num * 3600
            case "m": seconds += num * 60
            case "s": seconds += num
            default: break
            }
        }
        if seconds > 0 {
            return Date().addingTimeInterval(seconds)
        }

        // Try plain integer as seconds
        if let secs = TimeInterval(trimmed) {
            return Date().addingTimeInterval(secs)
        }

        return nil
    }

    private static func apiErrorSummary(statusCode: Int, data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let json = root as? [String: Any]
        else {
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !text.isEmpty
            {
                return Self.compactText(text)
            }
            return "Unexpected response body (\(data.count) bytes)."
        }

        if let message = json["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return Self.compactText(trimmed) }
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return Self.compactText(trimmed) }
        }

        return "HTTP \(statusCode) (\(data.count) bytes)."
    }

    private static func compactText(_ text: String, maxLength: Int = 200) -> String {
        let collapsed = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.count <= maxLength { return collapsed }
        let limitIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return "\(collapsed[..<limitIndex])..."
    }
}
