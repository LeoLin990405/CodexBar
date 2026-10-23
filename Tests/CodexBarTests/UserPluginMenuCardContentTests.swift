import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

#if canImport(JavaScriptCore)
struct UserPluginMenuCardContentTests {
    private var now: Date {
        Date(timeIntervalSinceReferenceDate: 805_000_000)
    }

    private func snapshot(usedPercent: Double = 42, capturedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 10080,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            tertiary: nil,
            updatedAt: capturedAt)
    }

    @Test
    func `clean success shows current usage without a stale marker`() {
        let content = UserPluginMenuCardContent.make(
            snapshot: self.snapshot(capturedAt: self.now.addingTimeInterval(-90)),
            error: nil,
            isRefreshing: false,
            now: self.now)
        #expect(content.usage == .current)
        #expect(content.showsUsageRows)
        #expect(!content.isStale)
        #expect(content.errorText == nil)
        #expect(content.lastKnownText == nil)
        #expect(content.placeholderText == nil)
    }

    @Test
    func `failed refresh keeps last-known usage with the error and its capture time`() {
        let capturedAt = self.now.addingTimeInterval(-600)
        let error = "The operation couldn’t be completed. (NSURLErrorDomain error -1004.)"
        let content = UserPluginMenuCardContent.make(
            snapshot: self.snapshot(capturedAt: capturedAt),
            error: error,
            isRefreshing: false,
            now: self.now)
        #expect(content.usage == .lastKnown)
        #expect(content.showsUsageRows)
        #expect(content.isStale)
        #expect(content.errorText == error)
        #expect(content.lastKnownText == LastKnownUsagePresentation.message(capturedAt: capturedAt, now: self.now))
        #expect(content.placeholderText == nil)
    }

    @Test
    func `failed first refresh shows the error without retained usage`() {
        let content = UserPluginMenuCardContent.make(
            snapshot: nil,
            error: "  Refresh failed: endpoint is offline. \n",
            isRefreshing: false,
            now: self.now)
        #expect(content.usage == .none)
        #expect(!content.showsUsageRows)
        #expect(!content.isStale)
        #expect(content.errorText == "Refresh failed: endpoint is offline.")
        #expect(content.lastKnownText == nil)
        #expect(content.placeholderText == nil)
    }

    @Test
    func `no snapshot and no error shows the no-usage placeholder`() {
        let content = UserPluginMenuCardContent.make(
            snapshot: nil,
            error: nil,
            isRefreshing: false,
            now: self.now)
        #expect(content.usage == .none)
        #expect(!content.showsUsageRows)
        #expect(content.errorText == nil)
        #expect(content.lastKnownText == nil)
        #expect(content.placeholderText == L("No usage fetched yet"))
    }

    @Test
    func `whitespace-only errors still read as a successful refresh`() {
        let content = UserPluginMenuCardContent.make(
            snapshot: self.snapshot(capturedAt: self.now),
            error: " \n\t ",
            isRefreshing: false,
            now: self.now)
        #expect(content.usage == .current)
        #expect(!content.isStale)
        #expect(content.errorText == nil)
        #expect(content.lastKnownText == nil)
    }

    @Test
    func `refreshing only swaps the header control and keeps the presented result`() {
        let snapshot = self.snapshot(capturedAt: self.now.addingTimeInterval(-120))
        let idle = UserPluginMenuCardContent.make(
            snapshot: snapshot,
            error: "Endpoint is offline.",
            isRefreshing: false,
            now: self.now)
        let refreshing = UserPluginMenuCardContent.make(
            snapshot: snapshot,
            error: "Endpoint is offline.",
            isRefreshing: true,
            now: self.now)
        #expect(!idle.isRefreshing)
        #expect(refreshing.isRefreshing)
        #expect(refreshing.usage == idle.usage)
        #expect(refreshing.errorText == idle.errorText)
        #expect(refreshing.lastKnownText == idle.lastKnownText)
    }

    @Test
    func `height cache fingerprint separates current, retained, and error-only states`() {
        let snapshot = self.snapshot(capturedAt: self.now)
        let empty = UserPluginMenuCardContent.fingerprint(snapshot: nil, error: nil)
        let current = UserPluginMenuCardContent.fingerprint(snapshot: snapshot, error: nil)
        let retained = UserPluginMenuCardContent.fingerprint(snapshot: snapshot, error: "Endpoint is offline.")
        let errorOnly = UserPluginMenuCardContent.fingerprint(snapshot: nil, error: "Endpoint is offline.")
        #expect(Set([empty, current, retained, errorOnly]).count == 4)
        #expect(UserPluginMenuCardContent.fingerprint(snapshot: snapshot, error: "Endpoint is offline.") == retained)
    }
}
#endif
