import Foundation

public struct TraeUsageSnapshot: Sendable {
    let checkLogin: TraeCheckLoginResult
    let profile: TraeProfileResult
    let stats: TraeStatsResult?
    public let updatedAt: Date
}

extension TraeUsageSnapshot {
    public func toUsageSnapshot() -> UsageSnapshot {
        let primary: RateWindow

        if let stats {
            // Sum 7-day AI interaction counts
            let total7d = (stats.codeAiAcceptCnt7d ?? 0) + (stats.codeCompCnt7d ?? 0)

            // Build model breakdown string
            let modelBreakdown = stats.codeCompDiffModelCnt7d?
                .sorted { $0.value > $1.value }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")

            let description = if let modelBreakdown, !modelBreakdown.isEmpty {
                "\(total7d) AI actions (7d) — \(modelBreakdown)"
            } else {
                "\(total7d) AI actions (7d)"
            }

            // Trae has no hard usage cap, so show activity level instead of percent
            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: description)
        } else {
            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Active — logged in")
        }

        let accountName = self.profile.screenName
            ?? self.checkLogin.userID
        let regionInfo = self.checkLogin.region ?? self.profile.aiRegion

        let identity = ProviderIdentitySnapshot(
            providerID: .trae,
            accountEmail: accountName,
            accountOrganization: regionInfo,
            loginMethod: self.profile.lastLoginType ?? "Web")

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}
