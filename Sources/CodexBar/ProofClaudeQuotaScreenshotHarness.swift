#if DEBUG
import AppKit
import CodexBarCore
import CoreGraphics
import SwiftUI

/// FORK-ONLY PROOF HARNESS — not intended for upstream.
///
/// Dropped onto the `proof/4687-app-proof` branch only so CI can screenshot the real
/// Settings window for a successful Claude answer that reports no quota windows (#4537).
///
/// Activation is file based: if `/tmp/codexbar-proof/` exists at launch, the harness runs.
/// It injects `UsageSnapshot(primary: nil, secondary: nil, updatedAt: now)` for `.claude`
/// through the existing DEBUG `UsageStore` hooks, opens the real Settings window on the
/// Claude provider pane, and reports the production subtitle / availability values as
/// runtime evidence and marker JSON the CI job captures with `screencapture -l`.
@MainActor
enum ProofClaudeQuotaScreenshotHarness {
    static let defaultDirectory = "/tmp/codexbar-proof"
    /// Keep in sync with the capture loop in `.github/workflows/proof-claude-app-screens.yml`.
    static let stepCount = 2

    private static var captureTask: Task<Void, Never>?

    static var isRequested: Bool {
        FileManager.default.fileExists(atPath: self.resolvedDirectory.path)
    }

    static var resolvedDirectory: URL {
        let path = ProcessInfo.processInfo.environment["CODEXBAR_PROOF_DIR"] ?? self.defaultDirectory
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func run(
        settings: SettingsStore,
        store: UsageStore,
        openSettings: @escaping @MainActor () -> Void,
        settingsWindow: @escaping @MainActor () -> NSWindow?)
    {
        guard self.isRequested else { return }
        let directory = self.resolvedDirectory
        self.log("harness enabled, directory=\(directory.path)")

        // Deterministic English copy, independent of the runner's system language.
        settings.appLanguage = "en"
        // Keep scheduled refreshes from racing the injected successful-but-quota-less answer.
        settings.refreshFrequency = .manual
        settings.setProviderEnabled(
            provider: .claude,
            metadata: store.metadata(for: .claude),
            enabled: true)
        // The headless runner has no Claude CLI/credentials, so the provider reports unavailable and
        // the settings UI would render its disabled placeholder. Force the enabled presentation so the
        // successful quota-less answer renders the way a configured user sees it.
        settings.providerEnablement[UsageProvider.claude.instanceID] = true

        let availabilityBefore = store.knownLimitsAvailability(for: .claude)
        let snapshot = self.injectQuotaLessClaudeSnapshot(store: store)
        self.printRuntimeEvidence(
            store: store,
            settings: settings,
            snapshot: snapshot,
            availabilityBefore: availabilityBefore,
            directory: directory)

        self.log("opening Settings on the Claude provider pane")
        openSettings()
        self.captureTask = Task { @MainActor in
            await self.captureSequence(
                settings: settings,
                store: store,
                directory: directory,
                availabilityBefore: availabilityBefore,
                settingsWindow: settingsWindow)
        }
    }

    /// The shipped app state for a successful Claude usage answer whose payload reports
    /// `five_hour: null` / `seven_day: null`: a fresh snapshot with no measured rate window,
    /// no cost surface and no error.
    @discardableResult
    private static func injectQuotaLessClaudeSnapshot(store: UsageStore) -> UsageSnapshot {
        store._setErrorForTesting(nil, provider: .claude)
        // The successful refresh path clears the remembered availability; keep it cleared so the
        // subtitle resolution has to come from the injected snapshot, as in production after a
        // successful refresh.
        store._setKnownLimitsAvailabilityForTesting(nil, provider: .claude)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Date())
        store._setSnapshotForTesting(snapshot, provider: .claude)
        return snapshot
    }

    private static func printRuntimeEvidence(
        store: UsageStore,
        settings: SettingsStore,
        snapshot: UsageSnapshot,
        availabilityBefore: UsageLimitsAvailability?,
        directory: URL)
    {
        let pane = ProvidersPane(provider: .claude, settings: settings, store: store)
        let providerSubtitle = pane._test_providerSubtitle(.claude)
        let providerSidebarSubtitle = pane._test_providerSidebarSubtitle(.claude)
        let cardModel = pane._test_menuCardModel(for: .claude)
        let resolved = UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot)
        let info = Bundle.main.infoDictionary ?? [:]
        let runtimeEvidence = [
            "scenario=successful-claude-web-answer-with-null-quota-windows-issue-4537",
            "injected.snapshot.primary=nil",
            "injected.snapshot.secondary=nil",
            "injected.snapshot.measuredRateWindows=\(snapshot.measuredRateWindows.count)",
            "injected.snapshot.hasRateLimitWindows=\(snapshot.hasRateLimitWindows)",
            "injected.snapshot.providerCost=\(snapshot.providerCost == nil ? "nil" : "present")",
            "injected.snapshot.updatedAt=\(ISO8601DateFormatter().string(from: snapshot.updatedAt))",
            "injected.snapshot.updatedAt.relativeDescription=\(snapshot.updatedAt.relativeDescription()) "
                + "(the value the pre-fix subtitle rendered)",
            "store.knownLimitsAvailability.before=\(self.describe(availabilityBefore))",
            "store.knownLimitsAvailability.afterInjection="
                + "\(self.describe(store.knownLimitsAvailability(for: .claude)))",
            "UsageLimitsAvailability.resolve=\(resolved)",
            "UsageLimitsAvailability.isUnavailable=\(resolved.isUnavailable)",
            "store.presentationSnapshot.present=\(store.presentationSnapshot(for: .claude) != nil)",
            "store.isStale=\(store.isStale(provider: .claude))",
            "settings.providerEnablement.forcedClaudeEnabled=true",
            "settings.isProviderEnabled="
                + "\(settings.isProviderEnabled(provider: .claude, metadata: store.metadata(for: .claude)))",
            "store.isEnabled.availabilityBased=\(store.isEnabled(.claude))",
            "providerDetail.usageSection.placeholder=\(cardModel.placeholder ?? "nil")",
            "providersPane.providerSubtitle=\(pendingLine(providerSubtitle))",
            "providersPane.providerSidebarSubtitle=\(pendingLine(providerSidebarSubtitle))",
            "providersPane.menuCard.placeholder=\(cardModel.placeholder ?? "nil")",
            "app.version=\(info["CFBundleShortVersionString"] as? String ?? "")",
            "app.build=\(info["CFBundleVersion"] as? String ?? "")",
            "app.gitCommit=\(info["CodexGitCommit"] as? String ?? "")",
            "app.bundleIdentifier=\(Bundle.main.bundleIdentifier ?? "")",
        ]
        for line in runtimeEvidence {
            self.log(line)
        }
        do {
            try runtimeEvidence.joined(separator: "\n")
                .appending("\n")
                .write(
                    to: directory.appendingPathComponent("runtime-evidence.txt"),
                    atomically: true,
                    encoding: .utf8)
        } catch {
            self.log("failed to write runtime evidence: \(error)")
        }
    }

    private static func captureSequence(
        settings: SettingsStore,
        store: UsageStore,
        directory: URL,
        availabilityBefore: UsageLimitsAvailability?,
        settingsWindow: @escaping @MainActor () -> NSWindow?) async
    {
        var window: NSWindow?
        let windowDeadline = Date().addingTimeInterval(180)
        while Date() < windowDeadline {
            if let candidate = settingsWindow(), candidate.isVisible, candidate.frame.width > 200 {
                window = candidate
                break
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        guard let window else {
            self.log("timed out waiting for the Settings window")
            self.writeMarker(
                directory: directory,
                payload: ["status": "window-timeout"],
                step: 0)
            return
        }
        self.log("Settings window visible: number=\(window.windowNumber) frame=\(window.frame)")

        // A tall window would capture the whole provider pane in one image; if AppKit clamps it to
        // the display, fall back to the screen area and walk scroll offsets instead.
        if let screen = window.screen ?? NSScreen.main {
            let tallFrame = NSRect(
                x: screen.visibleFrame.origin.x + 8,
                y: screen.visibleFrame.maxY - 1400,
                width: max(1000, screen.visibleFrame.width - 16),
                height: 1400)
            window.setFrame(tallFrame, display: true)
            if window.frame.height < 900 {
                var visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                visible.size.height = min(visible.height, 720)
                window.setFrame(visible, display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(2500))

        // Let any launch-time Claude refresh settle, then re-assert the successful quota-less state.
        for _ in 0..<40 {
            if !store.refreshingProviders.contains(UsageProvider.claude.instanceID) { break }
            try? await Task.sleep(for: .milliseconds(500))
        }

        let detail = self.detailScrollView(in: window)
        let maxOffset = self.maximumScrollOffset(for: detail)

        for step in 0..<self.stepCount {
            let snapshot = self.injectQuotaLessClaudeSnapshot(store: store)
            if step == 1 {
                self.applyScroll(detail, offset: min(260, maxOffset))
            }
            try? await Task.sleep(for: .milliseconds(1200))

            let pane = ProvidersPane(provider: .claude, settings: settings, store: store)
            let providerSubtitle = pane._test_providerSubtitle(.claude)
            let providerSidebarSubtitle = pane._test_providerSidebarSubtitle(.claude)
            let cardModel = pane._test_menuCardModel(for: .claude)
            let resolved = UsageLimitsAvailability.resolve(provider: .claude, snapshot: snapshot)
            let availabilityAfter = store.knownLimitsAvailability(for: .claude)
            let info = Bundle.main.infoDictionary ?? [:]
            let windowFrame: [Double] = [
                Double(window.frame.origin.x),
                Double(window.frame.origin.y),
                Double(window.frame.size.width),
                Double(window.frame.size.height),
            ]
            let payload: [String: Any] = [
                "status": "ready",
                "step": step,
                "stepCount": self.stepCount,
                "scrollOffset": Double(step == 1 ? min(260, maxOffset) : 0),
                "scrollMaxOffset": Double(maxOffset),
                "detailScrollViewFound": detail != nil,
                "scenario": "successful-claude-web-answer-with-null-quota-windows-issue-4537",
                "injectedSnapshotPrimaryNil": snapshot.primary == nil,
                "injectedSnapshotSecondaryNil": snapshot.secondary == nil,
                "injectedSnapshotMeasuredRateWindowCount": snapshot.measuredRateWindows.count,
                "injectedSnapshotHasRateLimitWindows": snapshot.hasRateLimitWindows,
                "injectedSnapshotProviderCostNil": snapshot.providerCost == nil,
                "injectedSnapshotUpdatedAt": ISO8601DateFormatter().string(from: snapshot.updatedAt),
                "injectedSnapshotRelativeDescription": snapshot.updatedAt.relativeDescription(),
                "knownLimitsAvailabilityBeforeInjection": self.describe(availabilityBefore),
                "knownLimitsAvailabilityAfterInjection": self.describe(availabilityAfter),
                "resolvedLimitsAvailability": String(describing: resolved),
                "resolvedLimitsAvailabilityIsUnavailable": resolved.isUnavailable,
                "presentationSnapshotPresent": store.presentationSnapshot(for: .claude) != nil,
                "providerStale": store.isStale(provider: .claude),
                "forcedClaudeEnabledForPresentation": true,
                "settingsIsProviderEnabled": settings.isProviderEnabled(
                    provider: .claude,
                    metadata: store.metadata(for: .claude)),
                "storeIsEnabledAvailabilityBased": store.isEnabled(.claude),
                "providerSubtitle": providerSubtitle,
                "providerDetailHeaderSubtitle": pendingLine(providerSubtitle),
                "providerSidebarSubtitle": providerSidebarSubtitle,
                "providerSidebarSubtitleInline": pendingLine(providerSidebarSubtitle),
                "menuCardPlaceholder": cardModel.placeholder ?? "nil",
                "providerDetailUsagePlaceholder": cardModel.placeholder ?? "nil",
                "windowNumber": window.windowNumber,
                "windowTitle": window.title,
                "windowFrame": windowFrame,
                "windowIsVisible": window.isVisible,
                "windowIsKey": window.isKeyWindow,
                "windowServer": self.windowServerInfo(windowNumber: window.windowNumber),
                "appLanguage": settings.appLanguage,
                "refreshFrequency": settings.refreshFrequency.rawValue,
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                "bundlePath": Bundle.main.bundlePath,
                "executablePath": Bundle.main.executablePath ?? "",
                "version": info["CFBundleShortVersionString"] as? String ?? "",
                "build": info["CFBundleVersion"] as? String ?? "",
                "gitCommit": info["CodexGitCommit"] as? String ?? "",
                "buildTimestamp": info["CodexBuildTimestamp"] as? String ?? "",
                "processID": ProcessInfo.processInfo.processIdentifier,
                "activationPolicy": NSApp.activationPolicy() == .regular
                    ? "regular"
                    : (NSApp.activationPolicy() == .accessory ? "accessory" : "prohibited"),
                "appIsActive": NSApp.isActive,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ]
            self.log("step \(step) window=\(window.windowNumber) subtitle=\(pendingLine(providerSubtitle))")
            self.writeMarker(directory: directory, payload: payload, step: step)

            guard step < self.stepCount - 1 else { break }
            let ackPath = directory.appendingPathComponent("next").path
            let ackDeadline = Date().addingTimeInterval(90)
            while Date() < ackDeadline {
                if FileManager.default.fileExists(atPath: ackPath) {
                    try? FileManager.default.removeItem(atPath: ackPath)
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        self.log("capture sequence complete")
    }

    private static func detailScrollView(in window: NSWindow) -> NSScrollView? {
        self.allScrollViews(in: window.contentView)
            .max(by: { $0.contentView.bounds.width < $1.contentView.bounds.width })
    }

    private static func allScrollViews(in view: NSView?) -> [NSScrollView] {
        guard let view else { return [] }
        var found: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            found.append(scrollView)
        }
        for subview in view.subviews {
            found.append(contentsOf: self.allScrollViews(in: subview))
        }
        return found
    }

    private static func maximumScrollOffset(for scrollView: NSScrollView?) -> CGFloat {
        guard let scrollView, let documentView = scrollView.documentView else { return 0 }
        return max(0, documentView.frame.height - scrollView.contentView.bounds.height)
    }

    private static func applyScroll(_ scrollView: NSScrollView?, offset: CGFloat) {
        guard let scrollView else { return }
        let point = NSPoint(x: scrollView.contentView.bounds.origin.x, y: offset)
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private static func windowServerInfo(windowNumber: Int) -> [String: Any] {
        let list = CGWindowListCopyWindowInfo(
            [.optionIncludingWindow],
            CGWindowID(windowNumber)) as? [[String: Any]] ?? []
        guard let info = list.first else { return ["found": false] }
        return [
            "found": true,
            "ownerName": info[kCGWindowOwnerName as String] as? String ?? "",
            "number": info[kCGWindowNumber as String] as? Int ?? -1,
            "layer": info[kCGWindowLayer as String] as? Int ?? -1,
            "onscreen": info[kCGWindowIsOnscreen as String] as? Bool ?? false,
            "alpha": info[kCGWindowAlpha as String] as? Double ?? -1,
            "bounds": String(describing: info[kCGWindowBounds as String] ?? ""),
        ]
    }

    private static func describe(_ availability: UsageLimitsAvailability?) -> String {
        guard let availability else { return "nil" }
        return String(describing: availability)
    }

    private static func pendingLine(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " • ")
    }

    private static func writeMarker(directory: URL, payload: [String: Any], step: Int) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            let stepURL = directory.appendingPathComponent("marker-step\(step).json")
            try data.write(to: stepURL, options: [.atomic])
            try data.write(to: directory.appendingPathComponent("marker.json"), options: [.atomic])
            self.log("wrote marker \(stepURL.path)")
        } catch {
            self.log("failed to write marker: \(error)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[proof-harness] \(message)\n".utf8))
    }
}
#endif
