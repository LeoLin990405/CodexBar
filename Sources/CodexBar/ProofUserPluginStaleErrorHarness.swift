#if DEBUG && canImport(JavaScriptCore)
import AppKit
import CodexBarCore

/// FORK-ONLY PROOF HARNESS — not intended for upstream.
///
/// Dropped onto the `proof/4733-app-proof` branch only so CI can screenshot the real status-item
/// menu for a user provider plugin whose refresh succeeded once and then failed (#4726).
///
/// Activation is file based: if `/tmp/codexbar-proof/` exists at launch, the harness runs.
/// A fixture plugin (written by the workflow to `~/.config/codexbar/providers/`) is discovered by
/// the production `UserProviderPluginRegistry`; the harness enables it, seeds the retained
/// successful snapshot plus the later refresh error through the store's state (no network, no
/// approval flow), reports the production card presentation values, then opens the real
/// status-item menu with the production `openMenuFromShortcut()` path so the card renders.
@MainActor
enum ProofUserPluginStaleErrorHarness {
    static let defaultDirectory = "/tmp/codexbar-proof"
    static let pluginIDRaw = "fixture-stale-proof"
    static let fixtureErrorText = "Usage request failed (HTTP 500): fixture endpoint stopped responding."

    static var isRequested: Bool {
        FileManager.default.fileExists(atPath: self.resolvedDirectory.path)
    }

    static var resolvedDirectory: URL {
        let path = ProcessInfo.processInfo.environment["CODEXBAR_PROOF_DIR"] ?? self.defaultDirectory
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func run(settings: SettingsStore, store: UsageStore, appDelegate: AppDelegate) {
        guard self.isRequested else { return }
        let directory = self.resolvedDirectory
        self.log("harness enabled, directory=\(directory.path)")

        // Deterministic English copy, independent of the runner's system language.
        settings.appLanguage = "en"
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false

        guard let pluginID = ProviderInstanceID(rawValue: self.pluginIDRaw),
              let plugin = UserProviderPluginRegistry.plugin(for: pluginID)
        else {
            let results = UserProviderPluginRegistry.allResults.map {
                "\($0.fileURL.lastPathComponent): \($0.error ?? "ok")"
            }
            self.log("ERROR: fixture plugin not registered: \(results)")
            self.writeMarker(
                directory: directory,
                payload: [
                    "status": "plugin-missing",
                    "pluginID": self.pluginIDRaw,
                    "loadResults": results,
                ])
            return
        }
        self.log("plugin registered: name=\(plugin.manifest.name) id=\(plugin.manifest.id.rawValue) "
            + "topLevel=\(plugin.manifest.topLevel) file=\(plugin.fileURL.lastPathComponent)")

        // Production enablement/selection path so the menu builds the plugin card.
        settings.setPluginEnabled(pluginID, enabled: true)
        settings.providerEnablement[pluginID] = true
        settings.selectedMenuProvider = pluginID

        Task { @MainActor in
            // Let any launch-time plugin refresh settle before seeding the success→failure state.
            for _ in 0..<40 {
                if !store.refreshingProviders.contains(pluginID) { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            self.applyScenario(
                settings: settings,
                store: store,
                plugin: plugin,
                pluginID: pluginID,
                directory: directory,
                appDelegate: appDelegate)
        }
    }

    private static func applyScenario(
        settings: SettingsStore,
        store: UsageStore,
        plugin: UserProviderPlugin,
        pluginID: ProviderInstanceID,
        directory: URL,
        appDelegate: AppDelegate)
    {
        // Success-first, failure-later: the snapshot below belongs to the last successful refresh
        // (captured a couple of minutes ago); the error belongs to the refresh that ran afterwards.
        let capturedAt = Date().addingTimeInterval(-125)
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 42,
                windowMinutes: 300,
                resetsAt: nil,
                resetDescription: nil),
            secondary: nil,
            updatedAt: capturedAt)
        store.snapshots[pluginID] = snapshot
        store.errors[pluginID] = self.fixtureErrorText
        store.refreshingProviders.remove(pluginID)

        // Production presentation state for the card.
        let content = UserPluginMenuCardContent.make(
            snapshot: snapshot,
            error: self.fixtureErrorText,
            isRefreshing: false)
        let lastKnownMessage = LastKnownUsagePresentation.message(capturedAt: snapshot.updatedAt)
        let topLevelCards = StatusItemController.userPluginsForMenu(
            UserProviderPluginRegistry.all,
            isEnabled: settings.isPluginEnabled,
            topLevelSwitcherVisible: true,
            selectedPluginID: pluginID)
        let nonMergedCards = StatusItemController.userPluginsForMenu(
            UserProviderPluginRegistry.all,
            isEnabled: settings.isPluginEnabled,
            topLevelSwitcherVisible: false,
            selectedPluginID: nil)
        let info = Bundle.main.infoDictionary ?? [:]
        let registryIDs = UserProviderPluginRegistry.all.map(\.manifest.id.rawValue)
        let errorText = content.errorText ?? ""
        let lastKnownText = content.lastKnownText ?? ""
        if content.usage != .lastKnown || lastKnownText.isEmpty {
            self.log("ERROR: unexpected card content usage=\(content.usage) lastKnown=\(lastKnownText)")
        }

        let payload: [String: Any] = [
            "status": "menu-open-requested",
            "scenario": "user-plugin-success-then-refresh-failure-retained-usage",
            "plugin.id": plugin.manifest.id.rawValue,
            "plugin.name": plugin.manifest.name,
            "plugin.topLevel": plugin.manifest.topLevel,
            "plugin.file": plugin.fileURL.lastPathComponent,
            "snapshot.primaryUsedPercent": snapshot.primary?.usedPercent ?? -1,
            "snapshot.primaryWindowMinutes": snapshot.primary?.windowMinutes ?? -1,
            "snapshot.secondaryPresent": snapshot.secondary != nil,
            "snapshot.updatedAt": ISO8601DateFormatter().string(from: snapshot.updatedAt),
            "snapshot.updatedAtRelative": snapshot.updatedAt.relativeDescription(),
            "error.text": self.fixtureErrorText,
            "card.usageState": content.usage.rawValue,
            "card.isStale": content.isStale,
            "card.showsUsageRows": content.showsUsageRows,
            "card.errorText": errorText,
            "card.lastKnownText": lastKnownText,
            "card.placeholderText": content.placeholderText ?? "nil",
            "card.isRefreshing": content.isRefreshing,
            "card.fingerprint": UserPluginMenuCardContent.fingerprint(
                snapshot: snapshot,
                error: self.fixtureErrorText),
            "lastKnownUsagePresentation.message": lastKnownMessage,
            "menu.userPluginsForMenu.topLevelSwitcherVisible": topLevelCards.map(\.manifest.id.rawValue),
            "menu.userPluginsForMenu.nonMerged": nonMergedCards.map(\.manifest.id.rawValue),
            "store.snapshotPresent": store.snapshots[pluginID] != nil,
            "store.errorPresent": store.errors[pluginID] != nil,
            "store.isRefreshing": store.refreshingProviders.contains(pluginID),
            "settings.isPluginEnabled": settings.isPluginEnabled(pluginID),
            "settings.mergeIcons": settings.mergeIcons,
            "settings.selectedMenuProvider": settings.selectedMenuProvider?.rawValue ?? "nil",
            "settings.refreshFrequency": settings.refreshFrequency.rawValue,
            "registry.pluginIDs": registryIDs,
            "statusItem.debug": appDelegate._proof_statusItemDebugDescription(),
            "app.version": info["CFBundleShortVersionString"] as? String ?? "",
            "app.build": info["CFBundleVersion"] as? String ?? "",
            "app.gitCommit": info["CodexGitCommit"] as? String ?? "",
            "app.bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "app.bundlePath": Bundle.main.bundlePath,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        let runtimeEvidence = [
            "scenario=user-plugin-success-then-refresh-failure-retained-usage",
            "plugin.id=\(plugin.manifest.id.rawValue) plugin.name=\(plugin.manifest.name)",
            "snapshot.primaryUsedPercent=42 snapshot.primaryWindowMinutes=300 snapshot.updatedAtRelative="
                + "\(snapshot.updatedAt.relativeDescription())",
            "error.text=\(self.fixtureErrorText)",
            "card.usageState=\(content.usage.rawValue) card.isStale=\(content.isStale) "
                + "card.showsUsageRows=\(content.showsUsageRows)",
            "card.errorText=\(errorText)",
            "card.lastKnownText=\(lastKnownText)",
            "card.placeholderText=\(content.placeholderText ?? "nil")",
            "menu.userPluginsForMenu.topLevelSwitcherVisible=\(topLevelCards.map(\.manifest.id.rawValue))",
            "menu.userPluginsForMenu.nonMerged=\(nonMergedCards.map(\.manifest.id.rawValue))",
            "settings.isPluginEnabled=\(settings.isPluginEnabled(pluginID)) "
                + "settings.mergeIcons=\(settings.mergeIcons) "
                + "settings.selectedMenuProvider=\(settings.selectedMenuProvider?.rawValue ?? "nil")",
            "store.snapshotPresent=\(store.snapshots[pluginID] != nil) "
                + "store.errorPresent=\(store.errors[pluginID] != nil)",
            "statusItem.debug=\(appDelegate._proof_statusItemDebugDescription())",
            "app.version=\(info["CFBundleShortVersionString"] as? String ?? "") "
                + "app.gitCommit=\(info["CodexGitCommit"] as? String ?? "")",
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
        self.writeMarker(directory: directory, payload: payload)

        // Give the workflow a moment to see the marker, then open the real status-item menu.
        self.log("opening the real status-item menu")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            appDelegate._proof_openStatusItemMenu()
        }
    }

    private static func writeMarker(directory: URL, payload: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("marker-menu.json"), options: [.atomic])
            try data.write(to: directory.appendingPathComponent("marker.json"), options: [.atomic])
            self.log("wrote marker \(directory.appendingPathComponent("marker-menu.json").path)")
        } catch {
            self.log("failed to write marker: \(error)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[proof-harness] \(message)\n".utf8))
    }
}
#endif
