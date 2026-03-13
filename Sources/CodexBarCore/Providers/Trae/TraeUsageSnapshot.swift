import Foundation

public struct TraeUsageSnapshot: Sendable {
    public let userInfo: TraeUserInfoResponse
    public let updatedAt: Date

    public init(userInfo: TraeUserInfoResponse, updatedAt: Date) {
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
        let data = self.userInfo.data

        // Build primary usage window from quota or usage info
        let primary: RateWindow
        if let usage = data?.usage {
            let used = usage.used ?? 0
            let total = usage.total ?? 0
            let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: Self.parseDate(usage.resetTime),
                resetDescription: "\(used)/\(total) requests")
        } else if let quota = data?.quota {
            let used = quota.used ?? 0
            let total = quota.total ?? 0
            let usedPercent = total > 0 ? Double(used) / Double(total) * 100 : 0
            primary = RateWindow(
                usedPercent: usedPercent,
                windowMinutes: nil,
                resetsAt: Self.parseDate(quota.resetTime),
                resetDescription: "\(used)/\(total) quota")
        } else {
            // No usage data available — report as active
            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Active")
        }

        let planName = data?.plan?.name ?? data?.plan?.type
        let identity = ProviderIdentitySnapshot(
            providerID: .trae,
            accountEmail: data?.email ?? data?.name,
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
