import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct ProviderRefreshCoordinatorTests {
    @Test
    func `coalesces provider refresh while one is in flight`() async {
        let coordinator = ProviderRefreshCoordinator()

        let first = await coordinator.begin(
            provider: .codex,
            reason: .runtimeSignal,
            force: false,
            minimumInterval: nil)
        let second = await coordinator.begin(
            provider: .codex,
            reason: .runtimeSignal,
            force: false,
            minimumInterval: nil)

        #expect(first == .run)
        #expect(second == .queued)
        #expect(await coordinator.finish(provider: .codex))

        let replay = await coordinator.begin(
            provider: .codex,
            reason: .coalesced,
            force: true,
            minimumInterval: nil)
        #expect(replay == .run)
        #expect(await coordinator.finish(provider: .codex) == false)
    }

    @Test
    func `throttles provider refresh inside minimum interval`() async {
        let coordinator = ProviderRefreshCoordinator()
        let now = Date()

        let first = await coordinator.begin(
            provider: .claude,
            reason: .timer,
            force: false,
            minimumInterval: 60,
            now: now)
        #expect(first == .run)
        #expect(await coordinator.finish(provider: .claude) == false)

        let second = await coordinator.begin(
            provider: .claude,
            reason: .timer,
            force: false,
            minimumInterval: 60,
            now: now.addingTimeInterval(10))
        #expect(second == .throttled)

        let forced = await coordinator.begin(
            provider: .claude,
            reason: .userInitiated,
            force: true,
            minimumInterval: 60,
            now: now.addingTimeInterval(10))
        #expect(forced == .run)
        #expect(await coordinator.finish(provider: .claude) == false)
    }
}
