import CodexBarCore
import Foundation

enum ProviderRefreshReason: String, Sendable {
    case startup
    case timer
    case settingsChanged
    case userInitiated
    case runtimeSignal
    case coalesced
}

enum ProviderRefreshAdmission: Sendable, Equatable {
    case run
    case queued
    case throttled
}

actor ProviderRefreshCoordinator {
    private var inFlight: Set<UsageProvider> = []
    private var pending: Set<UsageProvider> = []
    private var lastStartedAt: [UsageProvider: Date] = [:]

    func begin(
        provider: UsageProvider,
        reason _: ProviderRefreshReason,
        force: Bool,
        minimumInterval: TimeInterval?,
        now: Date = Date()) -> ProviderRefreshAdmission
    {
        if self.inFlight.contains(provider) {
            self.pending.insert(provider)
            return .queued
        }

        if !force,
           let minimumInterval,
           let lastStarted = self.lastStartedAt[provider],
           now.timeIntervalSince(lastStarted) < minimumInterval
        {
            return .throttled
        }

        self.inFlight.insert(provider)
        self.lastStartedAt[provider] = now
        return .run
    }

    func finish(provider: UsageProvider) -> Bool {
        self.inFlight.remove(provider)
        return self.pending.remove(provider) != nil
    }

    func reset(providers: Set<UsageProvider>? = nil) {
        guard let providers else {
            self.inFlight.removeAll()
            self.pending.removeAll()
            self.lastStartedAt.removeAll()
            return
        }
        for provider in providers {
            self.inFlight.remove(provider)
            self.pending.remove(provider)
            self.lastStartedAt.removeValue(forKey: provider)
        }
    }
}
