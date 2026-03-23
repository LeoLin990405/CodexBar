import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StepFunUsageSnapshot: Sendable {
    // API balance (prepaid account)
    public let balance: Double
    public let cashBalance: Double
    public let voucherBalance: Double
    public let accountType: String

    // Step Plan (coding subscription)
    public let planName: String?
    public let planExpiredAt: Date?
    public let planAutoRenew: Bool
    public let fiveHourLeftRate: Double?
    public let fiveHourResetTime: Date?
    public let weeklyLeftRate: Double?
    public let weeklyResetTime: Date?

    public let updatedAt: Date
    public let apiKeyValid: Bool

    public init(
        balance: Double,
        cashBalance: Double,
        voucherBalance: Double,
        accountType: String,
        planName: String? = nil,
        planExpiredAt: Date? = nil,
        planAutoRenew: Bool = false,
        fiveHourLeftRate: Double? = nil,
        fiveHourResetTime: Date? = nil,
        weeklyLeftRate: Double? = nil,
        weeklyResetTime: Date? = nil,
        updatedAt: Date,
        apiKeyValid: Bool = true)
    {
        self.balance = balance
        self.cashBalance = cashBalance
        self.voucherBalance = voucherBalance
        self.accountType = accountType
        self.planName = planName
        self.planExpiredAt = planExpiredAt
        self.planAutoRenew = planAutoRenew
        self.fiveHourLeftRate = fiveHourLeftRate
        self.fiveHourResetTime = fiveHourResetTime
        self.weeklyLeftRate = weeklyLeftRate
        self.weeklyResetTime = weeklyResetTime
        self.updatedAt = updatedAt
        self.apiKeyValid = apiKeyValid
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        // Primary: 5-hour rate limit (most relevant for active coding)
        let primary: RateWindow
        if let rate = self.fiveHourLeftRate {
            let usedPercent = max(0, min(100, (1.0 - rate) * 100))
            let pctStr = String(format: "%.0f%%", rate * 100)
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 5 * 60,
                resetsAt: self.fiveHourResetTime,
                resetDescription: "5h remaining: \(pctStr)")
        } else {
            // Fallback to balance display
            let balanceStr = String(format: "¥%.2f", self.balance)
            primary = RateWindow(
                usedPercent: self.balance > 0 ? max(0, min(100, 100 - self.balance)) : 100,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Balance: \(balanceStr)")
        }

        // Secondary: weekly rate limit
        var secondary: RateWindow?
        if let weekRate = self.weeklyLeftRate {
            let weekUsed = max(0, min(100, (1.0 - weekRate) * 100))
            let weekPctStr = String(format: "%.0f%%", weekRate * 100)
            secondary = RateWindow(
                usedPercent: weekUsed,
                windowMinutes: 7 * 24 * 60,
                resetsAt: self.weeklyResetTime,
                resetDescription: "Weekly remaining: \(weekPctStr)")
        }

        // Tertiary: plan info + balance
        var tertiary: RateWindow?
        if let planName = self.planName {
            var desc = "\(planName) Plan"
            if let exp = self.planExpiredAt {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                desc += " → \(formatter.string(from: exp))"
            }
            let balanceStr = String(format: "¥%.2f", self.balance)
            desc += " | Balance: \(balanceStr)"
            tertiary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: self.planExpiredAt,
                resetDescription: desc)
        }

        let org: String?
        if let planName = self.planName {
            org = "\(planName) Plan"
        } else {
            org = self.accountType == "prepaid" ? "Prepaid" : "Postpaid"
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .stepfun,
            accountEmail: nil,
            accountOrganization: org,
            loginMethod: nil)

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}

public enum StepFunUsageError: LocalizedError, Sendable {
    case missingCredentials
    case networkError(String)
    case apiError(Int, String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Missing StepFun API key (STEPFUN_API_KEY)."
        case let .networkError(message):
            "StepFun network error: \(message)"
        case let .apiError(code, message):
            "StepFun API error (\(code)): \(message)"
        case let .parseFailed(message):
            "Failed to parse StepFun response: \(message)"
        }
    }
}

public struct StepFunUsageFetcher: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.stepfunUsage)
    private static let accountsURL = URL(string: "https://api.stepfun.com/v1/accounts")!
    private static let planStatusURL =
        URL(string: "https://platform.stepfun.com/api/step.openapi.devcenter.Dashboard/GetStepPlanStatus")!
    private static let rateLimitURL =
        URL(string: "https://platform.stepfun.com/api/step.openapi.devcenter.Dashboard/QueryStepPlanRateLimit")!

    public static func fetchUsage(apiKey: String, oasisToken: String? = nil) async throws -> StepFunUsageSnapshot {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StepFunUsageError.missingCredentials
        }

        // 1. Fetch API balance (always works with API key)
        let (balance, cashBalance, voucherBalance, accountType) = try await self.fetchAccountBalance(apiKey: apiKey)

        // 2. Try to fetch Step Plan status + rate limits (needs oasis token from browser)
        var planName: String?
        var planExpiredAt: Date?
        var planAutoRenew = false
        var fiveHourLeftRate: Double?
        var fiveHourResetTime: Date?
        var weeklyLeftRate: Double?
        var weeklyResetTime: Date?

        if let token = oasisToken {
            // Fetch plan status
            if let planStatus = try? await self.fetchPlanStatus(oasisToken: token) {
                planName = planStatus.name
                planExpiredAt = planStatus.expiredAt
                planAutoRenew = planStatus.autoRenew
            }

            // Fetch rate limits
            if let rateLimit = try? await self.fetchRateLimit(oasisToken: token) {
                fiveHourLeftRate = rateLimit.fiveHourLeftRate
                fiveHourResetTime = rateLimit.fiveHourResetTime
                weeklyLeftRate = rateLimit.weeklyLeftRate
                weeklyResetTime = rateLimit.weeklyResetTime
            }
        }

        Self.log.debug(
            "StepFun balance=\(balance) plan=\(planName ?? "none") 5h=\(fiveHourLeftRate ?? -1) weekly=\(weeklyLeftRate ?? -1)")

        return StepFunUsageSnapshot(
            balance: balance,
            cashBalance: cashBalance,
            voucherBalance: voucherBalance,
            accountType: accountType,
            planName: planName,
            planExpiredAt: planExpiredAt,
            planAutoRenew: planAutoRenew,
            fiveHourLeftRate: fiveHourLeftRate,
            fiveHourResetTime: fiveHourResetTime,
            weeklyLeftRate: weeklyLeftRate,
            weeklyResetTime: weeklyResetTime,
            updatedAt: Date())
    }

    // MARK: - API Balance

    private static func fetchAccountBalance(apiKey: String) async throws -> (Double, Double, Double, String) {
        var request = URLRequest(url: self.accountsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StepFunUsageError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let summary = Self.errorSummary(data: data)
            Self.log.error("StepFun accounts API returned \(httpResponse.statusCode): \(summary)")
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw StepFunUsageError.apiError(httpResponse.statusCode, "Invalid API key")
            }
            throw StepFunUsageError.apiError(httpResponse.statusCode, summary)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StepFunUsageError.parseFailed("Invalid JSON response")
        }

        let balance = (json["balance"] as? Double) ?? 0
        let cashBalance = (json["total_cash_balance"] as? Double) ?? 0
        let voucherBalance = (json["total_voucher_balance"] as? Double) ?? 0
        let accountType = (json["type"] as? String) ?? "prepaid"

        return (balance, cashBalance, voucherBalance, accountType)
    }

    // MARK: - Step Plan Status

    private struct PlanStatus {
        let name: String
        let expiredAt: Date?
        let autoRenew: Bool
    }

    private static func fetchPlanStatus(oasisToken: String) async throws -> PlanStatus {
        var request = URLRequest(url: self.planStatusURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        Self.setOasisHeaders(request: &request, oasisToken: oasisToken)
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StepFunUsageError.apiError(0, "Plan status request failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subscription = json["subscription"] as? [String: Any]
        else {
            throw StepFunUsageError.parseFailed("Missing subscription data")
        }

        let name = (subscription["name"] as? String) ?? "Unknown"
        let autoRenew = (subscription["auto_renew"] as? Bool) ?? false
        var expiredAt: Date?
        if let expStr = subscription["expired_at"] as? String, let expTS = TimeInterval(expStr) {
            expiredAt = Date(timeIntervalSince1970: expTS)
        }

        return PlanStatus(name: name, expiredAt: expiredAt, autoRenew: autoRenew)
    }

    // MARK: - Rate Limits

    private struct RateLimit {
        let fiveHourLeftRate: Double
        let fiveHourResetTime: Date?
        let weeklyLeftRate: Double
        let weeklyResetTime: Date?
    }

    private static func fetchRateLimit(oasisToken: String) async throws -> RateLimit {
        var request = URLRequest(url: self.rateLimitURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "connect-protocol-version")
        Self.setOasisHeaders(request: &request, oasisToken: oasisToken)
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw StepFunUsageError.apiError(0, "Rate limit request failed")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StepFunUsageError.parseFailed("Invalid rate limit response")
        }

        let fiveHourRate = (json["five_hour_usage_left_rate"] as? Double) ?? 0
        let weeklyRate = (json["weekly_usage_left_rate"] as? Double) ?? 0

        var fiveHourReset: Date?
        if let ts = json["five_hour_usage_reset_time"] as? String, let tsNum = TimeInterval(ts) {
            fiveHourReset = Date(timeIntervalSince1970: tsNum)
        }

        var weeklyReset: Date?
        if let ts = json["weekly_usage_reset_time"] as? String, let tsNum = TimeInterval(ts) {
            weeklyReset = Date(timeIntervalSince1970: tsNum)
        }

        return RateLimit(
            fiveHourLeftRate: fiveHourRate,
            fiveHourResetTime: fiveHourReset,
            weeklyLeftRate: weeklyRate,
            weeklyResetTime: weeklyReset)
    }

    // MARK: - Helpers

    private static func setOasisHeaders(request: inout URLRequest, oasisToken: String) {
        // The Oasis-Token cookie contains access_token...refresh_token
        let parts = oasisToken.components(separatedBy: "...")
        let accessToken = parts.first ?? oasisToken
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Oasis-Token=\(oasisToken)", forHTTPHeaderField: "Cookie")
        request.setValue("https://platform.stepfun.com", forHTTPHeaderField: "Origin")
        request.setValue("https://platform.stepfun.com/plan-subscribe", forHTTPHeaderField: "Referer")
        let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
    }

    private static func errorSummary(data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
