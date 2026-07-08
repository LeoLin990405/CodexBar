import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@Suite(.serialized)
@MainActor
struct PerplexityRenewalPresentationTests {
    @Test
    func `menu descriptor shows perplexity renewal as a separate row`() throws {
        let suite = "PerplexityRenewalPresentationTests-menu"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.resetTimesShowAbsolute = false

        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing)
        let renewalDate = Date(timeIntervalSince1970: 1_743_000_000)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 25,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: "2500/10000 credits"),
                secondary: RateWindow(
                    usedPercent: 100,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: "0/0 bonus"),
                tertiary: RateWindow(
                    usedPercent: 100,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: "0/0 credits"),
                extraRateWindows: [
                    NamedRateWindow(
                        id: "renewal",
                        title: "Renews",
                        window: RateWindow(
                            usedPercent: 0,
                            windowMinutes: nil,
                            resetsAt: renewalDate,
                            resetDescription: nil)),
                ],
                updatedAt: Date(timeIntervalSince1970: 1_740_000_000),
                identity: ProviderIdentitySnapshot(
                    providerID: .perplexity,
                    accountEmail: nil,
                    accountOrganization: nil,
                    loginMethod: "Pro")),
            provider: .perplexity)

        let descriptor = MenuDescriptor.build(
            provider: .perplexity,
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updateReady: false,
            includeContextualActions: false)

        let lines = self.textLines(from: descriptor)
        #expect(lines.contains("Session: 75% left"))
        #expect(lines.contains("2500/10000 credits"))
        #expect(lines.contains("Renews: 100% left"))
        #expect(lines.contains(where: { $0.hasPrefix("Resets ") }))
    }

    @Test
    func `menu card shows perplexity renewal as extra metric and keeps credit detail`() throws {
        let now = Date(timeIntervalSince1970: 1_740_000_000)
        let metadata = try #require(ProviderDefaults.metadata[.perplexity])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 25,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "2500/10000 credits"),
            secondary: RateWindow(
                usedPercent: 100,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "0/0 bonus"),
            tertiary: RateWindow(
                usedPercent: 100,
                windowMinutes: nil,
                resetsAt: nil,
                resetDescription: "0/0 credits"),
            extraRateWindows: [
                NamedRateWindow(
                    id: "renewal",
                    title: "Renews",
                    window: RateWindow(
                        usedPercent: 0,
                        windowMinutes: nil,
                        resetsAt: now.addingTimeInterval(3600),
                        resetDescription: nil)),
            ],
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .perplexity,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Pro"))

        let model = UsageMenuCardView.Model.make(.init(
            provider: .perplexity,
            metadata: metadata,
            snapshot: snapshot,
            credits: nil,
            creditsError: nil,
            dashboard: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))

        #expect(model.metrics.map(\.title).contains("Renews"))
        #expect(model.metrics.first(where: { $0.id == "primary" })?.detailText == "2500/10000 credits")
        #expect(model.metrics.first(where: { $0.id == "primary" })?.resetText == nil)
    }

    private func textLines(from descriptor: MenuDescriptor) -> [String] {
        descriptor.sections
            .flatMap(\.entries)
            .compactMap { entry -> String? in
                guard case let .text(text, _) = entry else { return nil }
                return text
            }
    }
}
