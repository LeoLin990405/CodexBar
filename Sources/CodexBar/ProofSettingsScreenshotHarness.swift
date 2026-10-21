#if DEBUG
import AppKit
import CoreGraphics

/// FORK-ONLY PROOF HARNESS — not intended for upstream.
///
/// Exists only on the `proof/4680-app-proof` branch so a CI job with a real
/// WindowServer session can screenshot the actual Settings window of the built app.
///
/// Activation is deliberately file based so the harness also works when the app is
/// launched through LaunchServices (`open`), which does not inherit shell environment:
/// - If `/tmp/codexbar-proof/` (or `CODEXBAR_PROOF_DIR`) exists at launch, the harness runs.
/// - `<dir>/style` selects the menu bar style: `critters`, `bars`, or `iconAndPercent`.
/// - The harness selects the Menu Bar settings pane, applies the requested style through the
///   production `SettingsStore`, waits for the real `NSWindow`, then walks the pane's scroll
///   offsets. At every step it writes `<dir>/marker-<style>-step<N>.json` with the live
///   WindowServer window number and the production footer/enabled state; the CI job captures
///   each step with `screencapture -l` and acknowledges with a `<dir>/next` file.
@MainActor
enum ProofSettingsScreenshotHarness {
    static let defaultDirectory = "/tmp/codexbar-proof"
    /// Keep in sync with the capture loop in `.github/workflows/proof-app-screens.yml`.
    static let stepCount = 6

    private static var captureTask: Task<Void, Never>?

    static var isRequested: Bool {
        FileManager.default.fileExists(atPath: self.resolvedDirectory.path)
    }

    static var resolvedDirectory: URL {
        let path = ProcessInfo.processInfo.environment["CODEXBAR_PROOF_DIR"] ?? self.defaultDirectory
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func run(
        settings: SettingsStore?,
        openSettings: @MainActor () -> Void,
        settingsWindow: @MainActor () -> NSWindow?)
    {
        guard self.isRequested else { return }
        let directory = self.resolvedDirectory
        self.log("harness enabled, directory=\(directory.path)")

        guard let style = self.requestedStyle(in: directory) else {
            self.writeMarker(
                directory: directory,
                payload: ["status": "invalid-style"],
                styleName: "invalid",
                step: 0)
            return
        }
        self.log("requested style=\(style.rawValue)")

        // Deterministic English copy, independent of the runner's system language.
        settings?.appLanguage = "en"
        settings?.menuBarIconStyle = style

        self.log("opening Settings on the Menu Bar pane")
        openSettings()

        // Non-blocking: a previous blocking wait starved the main queue and missed the window.
        self.captureTask = Task { @MainActor in
            await self.captureSequence(
                settings: settings,
                style: style,
                directory: directory,
                settingsWindow: settingsWindow)
        }
    }

    private static func captureSequence(
        settings: SettingsStore?,
        style: MenuBarIconStyle,
        directory: URL,
        settingsWindow: @MainActor () -> NSWindow?) async
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
                styleName: style.rawValue,
                step: 0)
            return
        }
        self.log("Settings window visible: number=\(window.windowNumber) frame=\(window.frame)")

        // Use a window taller than the display: `screencapture -l` reads the window's
        // WindowServer surface, so the whole Menu Bar pane (style picker through Layout
        // footer) can appear in one image. The scroll sweep below is a fallback.
        if let screen = window.screen ?? NSScreen.main {
            let frame = NSRect(
                x: screen.visibleFrame.origin.x + 8,
                y: screen.visibleFrame.maxY - 1400,
                width: max(1000, screen.visibleFrame.width - 16),
                height: 1400)
            window.setFrame(frame, display: true)
            if window.frame.height < 900 {
                // AppKit/SwiftUI clamped the window to the display: use the screen area and
                // rely on the scroll sweep below to expose the Layout footer.
                var visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
                visible.size.height = min(visible.height, 720)
                window.setFrame(visible, display: true)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(2500))

        let detail = self.detailScrollView(in: window)
        let maxOffset = self.maximumScrollOffset(for: detail)
        let scrollViews = self.allScrollViews(in: window.contentView)
        self.log("scroll views=\(scrollViews.count) detail=\(detail != nil) maxOffset=\(maxOffset)")

        for step in 0..<self.stepCount {
            let fraction = CGFloat(step) / CGFloat(self.stepCount - 1)
            let offset = self.scrollOffset(fraction: fraction, maxOffset: maxOffset)
            self.applyScroll(detail, offset: offset)
            try? await Task.sleep(for: .milliseconds(900))

            let appliedStyle = settings?.menuBarIconStyle ?? style
            let editorEnabled = MenuBarPane.layoutEditorEnabled(for: appliedStyle)
            let footerKey = editorEnabled
                ? "menu_bar_layout_footer"
                : "menu_bar_layout_footer_requires_icon_and_percent"
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
                "scrollFraction": Double(fraction),
                "scrollOffset": Double(offset),
                "scrollMaxOffset": Double(maxOffset),
                "detailScrollViewFound": detail != nil,
                "scrollViewCount": scrollViews.count,
                "styleRequested": style.rawValue,
                "styleApplied": appliedStyle.rawValue,
                "editorEnabled": editorEnabled,
                "footerKey": footerKey,
                "footerText": MenuBarPane.layoutFooterText(for: appliedStyle),
                "localizedIconAndPercentLabel": MenuBarIconStyle.iconAndPercent.label,
                "windowNumber": window.windowNumber,
                "windowTitle": window.title,
                "windowFrame": windowFrame,
                "windowIsVisible": window.isVisible,
                "windowIsKey": window.isKeyWindow,
                "appLanguage": settings?.appLanguage ?? "",
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
                "windowServer": self.windowServerInfo(windowNumber: window.windowNumber),
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ]
            self.log("step \(step) scroll=\(offset) window=\(window.windowNumber) "
                + "editorEnabled=\(editorEnabled)")
            self.writeMarker(
                directory: directory,
                payload: payload,
                styleName: style.rawValue,
                step: step)

            guard step < self.stepCount - 1 else { break }
            // Wait for the CI job to capture this step before scrolling further.
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

    /// The detail pane is the widest scroll view; the sidebar is a narrower sibling.
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

    private static func scrollOffset(fraction: CGFloat, maxOffset: CGFloat) -> CGFloat {
        // The Layout editor is tall; spread the sweep over the whole scrollable range.
        let raw = maxOffset * fraction
        return (raw * 10).rounded() / 10
    }

    private static func applyScroll(_ scrollView: NSScrollView?, offset: CGFloat) {
        guard let scrollView else { return }
        let point = NSPoint(x: scrollView.contentView.bounds.origin.x, y: offset)
        scrollView.contentView.scroll(to: point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Cross-check that the WindowServer really owns this window number (same list `screencapture -l`
    /// resolves), and that the surface bounds match the AppKit frame.
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
            "bounds": info[kCGWindowBounds as String] ?? "",
        ]
    }

    private static func requestedStyle(in directory: URL) -> MenuBarIconStyle? {
        let environment = ProcessInfo.processInfo.environment["CODEXBAR_PROOF_MENUBAR_STYLE"]
        let fileStyle = try? String(contentsOf: directory.appendingPathComponent("style"), encoding: .utf8)
        for candidate in [environment, fileStyle] {
            let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let style = MenuBarIconStyle(rawValue: raw) { return style }
        }
        return nil
    }

    private static func writeMarker(
        directory: URL,
        payload: [String: Any],
        styleName: String,
        step: Int)
    {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            let stepURL = directory.appendingPathComponent("marker-\(styleName)-step\(step).json")
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
