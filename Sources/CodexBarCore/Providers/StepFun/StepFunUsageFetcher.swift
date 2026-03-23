import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StepFunUsageSnapshot: Sendable {
    public let balance: Double
    public let cashBalance: Double
    public let voucherBalance: Double
    public let accountType: String
    public let updatedAt: Date
    public let apiKeyValid: Bool

    public init(
        balance: Double,
        cashBalance: Double,
        voucherBalance: Double,
        accountType: String,
        updatedAt: Date,
        apiKeyValid: Bool = true)
    {
        self.balance = balance
        self.cashBalance = cashBalance
        self.voucherBalance = voucherBalance
        self.accountType = accountType
        self.updatedAt = updatedAt
        self.apiKeyValid = apiKeyValid
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let resetDescription: String
        if self.apiKeyValid {
            let balanceStr = String(format: "¥%.2f", self.balance)
            var detail = "Balance: \(balanceStr)"
            if self.voucherBalance > 0 {
                let voucherStr = String(format: "¥%.2f", self.voucherBalance)
                detail += " (voucher: \(voucherStr))"
            }
            resetDescription = detail
        } else {
            resetDescription = "No usage data"
        }

        // Show balance as percentage (assume ¥100 as reasonable full scale for display)
        // If balance is high, cap at low percent used; if low, show high percent used
        let usedPercent: Double
        if self.balance > 0 {
            // Invert: more balance = less "used"
            // Use log scale for better display: 0 = 100% used, 100+ = ~0% used
            usedPercent = max(0, min(100, 100 - self.balance))
        } else {
            usedPercent = 100
        }

        let primary = RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: resetDescription)

        let identity = ProviderIdentitySnapshot(
            providerID: .stepfun,
            accountEmail: nil,
            accountOrganization: self.accountType == "prepaid" ? "Prepaid" : "Postpaid",
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

    public static func fetchUsage(apiKey: String) async throws -> StepFunUsageSnapshot {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StepFunUsageError.missingCredentials
        }

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
            Self.log.error("StepFun API returned \(httpResponse.statusCode): \(summary)")

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

        Self.log.debug(
            "StepFun balance=\(balance) cash=\(cashBalance) voucher=\(voucherBalance) type=\(accountType)")

        return StepFunUsageSnapshot(
            balance: balance,
            cashBalance: cashBalance,
            voucherBalance: voucherBalance,
            accountType: accountType,
            updatedAt: Date())
    }

    private static func errorSummary(data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String
        {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
}
