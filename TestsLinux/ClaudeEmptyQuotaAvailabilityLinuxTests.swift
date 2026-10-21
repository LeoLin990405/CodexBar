#if os(Linux)
import Foundation
import Testing
@testable import CodexBarCore

/// Fork-only proof mirror of `Tests/CodexBarTests/ClaudeEmptyQuotaAvailabilityTests.swift`
/// (issue #4537). The macOS suite cannot run on a contributor machine without Xcode, so the
/// core availability regression is exercised through the Linux test target instead.
struct ClaudeEmptyQuotaAvailabilityLinuxTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `Claude Free web payload with null quota fields yields no rate windows`() throws {
        let payload = Data(#"{"five_hour":null,"seven_day":null}"#.utf8)
        let web = try ClaudeWebAPIFetcher._parseUsageResponseForTesting(payload)

        #expect(web.sessionPercentUsed == nil)
        #expect(web.weeklyPercentUsed == nil)
        #expect(web.opusPercentUsed == nil)
        #expect(web.extraRateWindows.isEmpty)
        #expect(web.extraUsageCost == nil)
    }

    @Test
    func `quota-less Claude snapshot reports limits unavailable`() {
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Self.now)

        #expect(UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot) == .unavailable)
    }

    @Test
    func `spend-only Claude snapshot stays available`() {
        let snapshot = UsageSnapshot(
            primary: nil,
            secondary: nil,
            providerCost: ProviderCostSnapshot(
                used: 9.95,
                limit: 150,
                currencyCode: "USD",
                period: "Monthly cap",
                updatedAt: Self.now),
            updatedAt: Self.now)

        #expect(UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot) == .available)
    }

    @Test
    func `measured Claude quota window stays available`() {
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 12,
                windowMinutes: 5 * 60,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: Self.now)

        #expect(UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot) == .available)
    }

    @Test
    func `synthetic Claude placeholder stays unavailable`() {
        let placeholder = RateWindow(
            usedPercent: 0,
            windowMinutes: 5 * 60,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true)
        let snapshot = UsageSnapshot(primary: placeholder, secondary: nil, updatedAt: Self.now)

        #expect(UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot) == .unavailable)
    }

    @Test
    func `nil snapshot without an error stays available`() {
        #expect(UsageLimitsAvailability.resolve(provider: .claude, snapshot: nil) == .available)
        #expect(UsageLimitsAvailability.resolve(
            provider: .claude,
            snapshot: nil,
            lastErrorDescription: ClaudeStatusProbe.subscriptionQuotaUnavailableDescription) == .unavailable)
    }
}
#endif
