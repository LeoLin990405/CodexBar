#if DEBUG
import AppKit

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
///   production `SettingsStore`, waits for the real `NSWindow` to be on screen, then writes
///   `<dir>/marker-<style>.json` with the WindowServer window number plus the production
///   footer/enabled state so the CI job can capture it with `screencapture -l`.
@MainActor
enum ProofSettingsScreenshotHarness {
    static let defaultDirectory = "/tmp/codexbar-proof"

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
                styleName: "invalid")
            return
        }
        self.log("requested style=\(style.rawValue)")

        // Deterministic English copy, independent of the runner's system language.
        settings?.appLanguage = "en"
        settings?.menuBarIconStyle = style

        self.log("opening Settings on the Menu Bar pane")
        openSettings()

        var window: NSWindow?
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let candidate = settingsWindow(), candidate.isVisible, candidate.frame.width > 200 {
                window = candidate
                break
            }
        }
        guard let window else {
            self.log("timed out waiting for the Settings window")
            self.writeMarker(
                directory: directory,
                payload: ["status": "window-timeout"],
                styleName: style.rawValue)
            return
        }

        // Use the available screen area so the whole Menu Bar pane (including the Layout
        // section footer that is the subject of the PR) is visible in one frame.
        if let screen = window.screen ?? NSScreen.main {
            var frame = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            frame.size.height = min(frame.size.height, 720)
            window.setFrame(frame, display: true)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        // Let SwiftUI finish layout (the style change toggles the editor's disabled state).
        let settleDeadline = Date().addingTimeInterval(3)
        while Date() < settleDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }

        let appliedStyle = settings?.menuBarIconStyle
        let styleForEvidence = appliedStyle ?? style
        let editorEnabled = MenuBarPane.layoutEditorEnabled(for: styleForEvidence)
        let footerText = MenuBarPane.layoutFooterText(for: styleForEvidence)
        let footerKey = editorEnabled
            ? "menu_bar_layout_footer"
            : "menu_bar_layout_footer_requires_icon_and_percent"
        let info = Bundle.main.infoDictionary ?? [:]
        let battery = [
            "status": "ready",
            "styleRequested": style.rawValue,
            "styleApplied": styleForEvidence.rawValue,
            "editorEnabled": editorEnabled,
            "footerKey": footerKey,
            "footerText": footerText,
            "localizedIconAndPercentLabel": MenuBarIconStyle.iconAndPercent.label,
            "windowNumber": window.windowNumber,
            "windowTitle": window.title,
            "windowFrame": [
                Double(window.frame.origin.x),
                Double(window.frame.origin.y),
                Double(window.frame.size.width),
                Double(window.frame.size.height),
            ],
            "windowIsVisible": window.isVisible,
            "windowIsKey": window.isKeyWindow,
            "screenFrame": (window.screen ?? NSScreen.main).map {
                [
                    Double($0.frame.origin.x),
                    Double($0.frame.origin.y),
                    Double($0.frame.size.width),
                    Double($0.frame.size.height),
                ]
            } ?? [],
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
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ] as [String: Any]
        self.log("window ready: number=\(window.windowNumber) frame=\(window.frame) "
            + "editorEnabled=\(editorEnabled) footer=\(footerText)")
        self.writeMarker(directory: directory, payload: battery, styleName: style.rawValue)
    }

    private static func requestedStyle(in directory: URL) -> MenuBarIconStyle? {
        let environment = ProcessInfo.processInfo.environment["CODEXBAR_PROOF_MENUBAR_STYLE"]
        let fileStyle = try? String(contentsOf: directory.appendingPathComponent("style"), encoding: .utf8)
        let candidates = [environment, fileStyle]
        for candidate in candidates {
            let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let style = MenuBarIconStyle(rawValue: raw) { return style }
        }
        return nil
    }

    private static func writeMarker(directory: URL, payload: [String: Any], styleName: String) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            let styleURL = directory.appendingPathComponent("marker-\(styleName).json")
            try data.write(to: styleURL, options: [.atomic])
            try data.write(to: directory.appendingPathComponent("marker.json"), options: [.atomic])
            self.log("wrote marker \(styleURL.path)")
        } catch {
            self.log("failed to write marker: \(error)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[proof-harness] \(message)\n".utf8))
    }
}
#endif
