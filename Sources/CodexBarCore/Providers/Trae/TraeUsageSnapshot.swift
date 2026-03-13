import Foundation

public struct TraeUsageSnapshot: Sendable {
    let checkLogin: TraeCheckLoginResult
    let userInfo: TraeUserInfoResult
    public let updatedAt: Date

    init(checkLogin: TraeCheckLoginResult, userInfo: TraeUserInfoResult, updatedAt: Date) {
        self.checkLogin = checkLogin
        self.userInfo = userInfo
        self.updatedAt = updatedAt
    }

    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString, !dateString.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) { return date }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: dateString)
    }
}

extension TraeUsageSnapshot {
    public func toUsageSnapshot() -> UsageSnapshot {
        // Build primary usage window from usage or quota info
        let primary: RateWindow
        if let usage = self.userInfo.usage {
            let used = usage.used ?? 0
            let total = usage.total ?? 0
            let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: Self.parseDate(usage.resetTime),
                resetDescription: "\(used)/\(total) requests")
        } else if let quota = self.userInfo.quota {
            let used = quota.used ?? 0
            let total = quota.total ?? 0
            let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: Self.parseDate(quota.resetTime),
                resetDescription: "\(used)/\(total) quota")
        } else {
            // No usage data from GetUserInfo — report as active with login info
            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Active — logged in")
        }

        let planName = self.userInfo.plan
        let accountName = self.userInfo.email ?? self.userInfo.userName ?? self.checkLogin.userID
        let identity = ProviderIdentitySnapshot(
            providerID: .trae,
            accountEmail: accountName,
            accountOrganization: nil,
            loginMethod: planName ?? "Web")

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}
