import Foundation

public struct TraeUsageSnapshot: Sendable {
    let checkLogin: TraeCheckLoginResult
    let profile: TraeProfileResult
    let stats: TraeStatsResult?
    let entitlements: TraeEntitlementList?
    public let updatedAt: Date

    public init(
        checkLogin: TraeCheckLoginResult,
        profile: TraeProfileResult,
        stats: TraeStatsResult?,
        entitlements: TraeEntitlementList? = nil,
        updatedAt: Date)
    {
        self.checkLogin = checkLogin
        self.profile = profile
        self.stats = stats
        self.entitlements = entitlements
        self.updatedAt = updatedAt
    }
}

extension TraeUsageSnapshot {
    public func toUsageSnapshot() -> UsageSnapshot {
        // Prefer dollar-usage bars when entitlements are available
        // (Pro plan + optional Extra package), then fall back to 7-day activity.
        let primary: RateWindow
        let secondary: RateWindow?

        if let packs = self.entitlements?.userEntitlementPackList, !packs.isEmpty {
            let proPack = packs.first { ($0.displayDesc ?? "").lowercased().contains("pro") }
                ?? packs[0]
            primary = Self.makeDollarWindow(from: proPack)

            let proLabel = proPack.displayDesc
            let extraPack = packs.first { pack in
                pack.displayDesc != proLabel
                    && (pack.displayDesc?.lowercased().contains("extra") ?? false)
            }
            secondary = extraPack.map { Self.makeDollarWindow(from: $0) }
        } else if let stats {
            let total7d = (stats.codeAiAcceptCnt7d ?? 0) + (stats.codeCompCnt7d ?? 0)
            let modelBreakdown = stats.codeCompDiffModelCnt7d?
                .sorted { $0.value > $1.value }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")

            let description = if let modelBreakdown, !modelBreakdown.isEmpty {
                "\(total7d) AI actions (7d) — \(modelBreakdown)"
            } else {
                "\(total7d) AI actions (7d)"
            }

            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: 7 * 24 * 60,
                resetsAt: nil,
                resetDescription: description)
            secondary = nil
        } else {
            primary = RateWindow(
                usedPercent: 0,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "Active — logged in")
            secondary = nil
        }

        let accountName = self.profile.screenName ?? self.checkLogin.userID
        let regionInfo = self.checkLogin.region ?? self.profile.aiRegion

        let identity = ProviderIdentitySnapshot(
            providerID: .trae,
            accountEmail: accountName,
            accountOrganization: regionInfo,
            loginMethod: self.profile.lastLoginType ?? "Web")

        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }

    private static func makeDollarWindow(from pack: TraeEntitlementPack) -> RateWindow {
        let usage = pack.usage
        let used = (usage?.basicUsageAmount ?? 0) + (usage?.bonusUsageAmount ?? 0)
        let limit = (pack.entitlementBaseInfo?.productExtra?.packageExtra?.quota?.basicUsageLimit ?? 0)
            + (pack.entitlementBaseInfo?.productExtra?.packageExtra?.quota?.bonusUsageLimit ?? 0)
        let percent: Double = limit > 0
            ? min(100, max(0, used / limit * 100))
            : 0
        let resetsAt: Date? = pack.nextBillingTime.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        } ?? pack.entitlementBaseInfo?.endTime.flatMap {
            $0 > 0 ? Date(timeIntervalSince1970: $0) : nil
        }
        let label = pack.displayDesc ?? "Plan"
        let description = limit > 0
            ? String(format: "%@: $%.2f / $%.2f", label, used, limit)
            : String(format: "%@: $%.2f used", label, used)
        return RateWindow(
            usedPercent: percent,
            windowMinutes: nil,
            resetsAt: resetsAt,
            resetDescription: description)
    }
}
