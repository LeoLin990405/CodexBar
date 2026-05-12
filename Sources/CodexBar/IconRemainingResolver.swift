import CodexBarCore

enum IconRemainingResolver {
    private static func codexProjection(snapshot: UsageSnapshot) -> CodexConsumerProjection {
        CodexConsumerProjection.make(
            surface: .menuBar,
            context: CodexConsumerProjection.Context(
                snapshot: snapshot,
                rawUsageError: nil,
                liveCredits: nil,
                rawCreditsError: nil,
                liveDashboard: nil,
                rawDashboardError: nil,
                dashboardAttachmentAuthorized: false,
                dashboardRequiresLogin: false,
                now: snapshot.updatedAt))
    }

    private static func codexVisibleWindows(snapshot: UsageSnapshot) -> [RateWindow] {
        let projection = self.codexProjection(snapshot: snapshot)
        return projection.visibleRateLanes.compactMap { projection.rateWindow(for: $0) }
    }

    static func resolvedWindows(
        snapshot: UsageSnapshot,
        style: IconStyle)
        -> (primary: RateWindow?, secondary: RateWindow?)
    {
        if style == .perplexity {
            let windows = snapshot.orderedPerplexityDisplayWindows()
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .antigravity {
            let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .codex {
            let windows = self.codexVisibleWindows(snapshot: snapshot)
            return (
                primary: windows.first,
                secondary: windows.dropFirst().first)
        }
        if style == .zai {
            return (
                primary: snapshot.primary,
                secondary: snapshot.tertiary ?? snapshot.secondary)
        }
        return (
            primary: snapshot.primary,
            secondary: snapshot.secondary)
    }

    static func resolvedRemaining(
        snapshot: UsageSnapshot,
        style: IconStyle)
        -> (primary: Double?, secondary: Double?)
    {
        // Share lane selection with resolvedWindows so that resolvedRemaining,
        // resolvedWindows, and resolvedPercents all stay in agreement for every
        // style (z.ai, codex, perplexity, antigravity, …).
        let windows = Self.resolvedWindows(snapshot: snapshot, style: style)
        return (
            primary: windows.primary?.remainingPercent,
            secondary: windows.secondary?.remainingPercent)
    }

    static func resolvedPercents(
        snapshot: UsageSnapshot,
        style: IconStyle,
        showUsed: Bool)
        -> (primary: Double?, secondary: Double?)
    {
        let windows = Self.resolvedWindows(snapshot: snapshot, style: style)
        return (
            primary: showUsed ? windows.primary?.usedPercent : windows.primary?.remainingPercent,
            secondary: showUsed ? windows.secondary?.usedPercent : windows.secondary?.remainingPercent)
    }
}
