#if DEBUG && canImport(JavaScriptCore)
import AppKit
import CodexBarCore

/// FORK-ONLY PROOF HARNESS — not intended for upstream.
///
/// Dropped onto the `proof/4733-app-proof` branch only so CI can screenshot the real status-item
/// menu for a user provider plugin across the refresh states of issue #4726. It drives the
/// production refresh path (`UsageStore.refreshUserPlugin` + `ProviderPluginApprovalStore`) against
/// a loopback fixture server, then opens the real status-item menu via the production
/// `StatusItemController.openMenuFromShortcut()` path so the production plugin card renders.
///
/// Activation is file based: if `/tmp/codexbar-proof/` exists at launch, the harness runs.
/// `<dir>/state` selects the scenario: `success`, `success-failure`, `failure-only`, `recovery`.
/// The loopback server reads `<dir>/server_mode` (`success` or `fail`) on every request.
@MainActor
enum ProofUserPluginStaleErrorHarness {
    static let defaultDirectory = "/tmp/codexbar-proof"
    static let pluginIDRaw = "fixture-stale-proof"
    static let baseURLSettingKey = "BASE_URL"
    static let baseURLValue = "http://127.0.0.1:8765"
    /// Gap between the successful refresh and the later failure so the retained card shows a
    /// non-zero capture age in "Showing last-known usage captured …".
    static let retainedAgeSeconds: UInt64 = 70

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
        let stateName = (try? String(contentsOf: directory.appendingPathComponent("state"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "success-failure"
        self.log("harness enabled, directory=\(directory.path) state=\(stateName)")

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
                state: stateName,
                payload: [
                    "status": "plugin-missing",
                    "pluginID": self.pluginIDRaw,
                    "loadResults": results,
                ])
            return
        }
        self.log("plugin registered: name=\(plugin.manifest.name) id=\(plugin.manifest.id.rawValue) "
            + "topLevel=\(plugin.manifest.topLevel) file=\(plugin.fileURL.lastPathComponent)")

        // Production enablement/selection so the menu builds the plugin card.
        settings.providerEnablement[pluginID] = true
        settings.selectedMenuProvider = pluginID
        let pluginConfig = self.configurePlugin(settings: settings, plugin: plugin, pluginID: pluginID)

        Task { @MainActor in
            await self.waitForQuietStore(store, pluginID: pluginID)
            await self.applyScenario(
                stateName: stateName,
                settings: settings,
                store: store,
                plugin: plugin,
                pluginID: pluginID,
                pluginConfig: pluginConfig,
                directory: directory,
                appDelegate: appDelegate)
        }
    }

    /// Configures the plugin's BASE_URL (production config path) and records the production typed
    /// approval binding for the loopback origin so real refreshes are allowed.
    private static func configurePlugin(
        settings: SettingsStore,
        plugin: UserProviderPlugin,
        pluginID: ProviderInstanceID) -> [String: String]
    {
        if settings.pluginConfig(pluginID)?.pluginSettings?[self.baseURLSettingKey] != self.baseURLValue {
            settings.updatePluginConfig(instanceID: pluginID) { entry in
                var values = entry.pluginSettings ?? [:]
                values[self.baseURLSettingKey] = self.baseURLValue
                entry.pluginSettings = values
            }
        }
        let pluginSettings = settings.pluginConfig(pluginID)?.pluginSettings ?? [:]
        do {
            let binding = try plugin.approvalBinding(settings: pluginSettings)
            try ProviderPluginApprovalStore().record(binding)
            self.log("plugin approval recorded origins=\(binding.origins) settings=\(pluginSettings.keys.sorted())")
        } catch {
            self.log("ERROR: plugin approval failed: \(error)")
        }
        return pluginSettings
    }

    /// Waits until the plugin has not been refreshing for six consecutive checks (~1.5 seconds).
    private static func waitForQuietStore(_ store: UsageStore, pluginID: ProviderInstanceID) async {
        var quietChecks = 0
        for _ in 0..<120 {
            if store.refreshingProviders.contains(pluginID) {
                quietChecks = 0
            } else {
                quietChecks += 1
                if quietChecks >= 6 { return }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private static func modes(for state: String) -> [String] {
        switch state {
        case "success": ["success"]
        case "failure-only": ["fail"]
        case "recovery": ["success", "fail", "success"]
        default: ["success", "fail"]
        }
    }

    private static func applyScenario(
        stateName: String,
        settings: SettingsStore,
        store: UsageStore,
        plugin: UserProviderPlugin,
        pluginID: ProviderInstanceID,
        pluginConfig: [String: String],
        directory: URL,
        appDelegate: AppDelegate) async
    {
        var steps: [[String: Any]] = []
        var previousMode: String?
        for mode in self.modes(for: stateName) {
            // Keep the retained snapshot old enough that the last-known line shows a real age.
            if previousMode == "success", mode == "fail" {
                self.log("waiting \(self.retainedAgeSeconds)s before the failing refresh")
                try? await Task.sleep(for: .milliseconds(Int64(self.retainedAgeSeconds) * 1000))
            }
            self.writeServerMode(mode, directory: directory)
            try? await Task.sleep(for: .milliseconds(350))
            self.log("production refresh step mode=\(mode)")
            await store.refreshUserPlugin(pluginID)
            for _ in 0..<80 {
                if !store.refreshingProviders.contains(pluginID) { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .milliseconds(250))
            let snapshot = store.snapshots[pluginID]
            let error = store.errors[pluginID]
            steps.append([
                "mode": mode,
                "snapshotPresent": snapshot != nil,
                "snapshot.primaryUsedPercent": snapshot?.primary?.usedPercent ?? -1,
                "snapshot.updatedAtRelative": snapshot.map { $0.updatedAt.relativeDescription() } ?? "nil",
                "error": error ?? "nil",
            ])
            self.log("step mode=\(mode) snapshotPresent=\(snapshot != nil) "
                + "usedPercent=\(snapshot?.primary?.usedPercent ?? -1) error=\(error ?? "nil")")
            previousMode = mode
        }

        await self.waitForQuietStore(store, pluginID: pluginID)
        let snapshot = store.snapshots[pluginID]
        let error = store.errors[pluginID]
        let content = UserPluginMenuCardContent.make(
            snapshot: snapshot,
            error: error,
            isRefreshing: false)
        let lastKnownMessage = LastKnownUsagePresentation.message(capturedAt: snapshot?.updatedAt ?? Date())
        let observedErrorText = content.errorText ?? ""
        let lastKnownText = content.lastKnownText ?? ""
        let info = Bundle.main.infoDictionary ?? [:]
        let registryIDs = UserProviderPluginRegistry.all.map(\.manifest.id.rawValue)
        let statusItem = appDelegate._proof_statusItemDebugDescription()
        let menuPluginIDs = StatusItemController.userPluginsForMenu(
            UserProviderPluginRegistry.all,
            isEnabled: settings.isPluginEnabled,
            topLevelSwitcherVisible: false,
            selectedPluginID: nil).map(\.manifest.id.rawValue)

        let payload: [String: Any] = [
            "status": "menu-open-requested",
            "scenario": "user-plugin-success-then-refresh-failure-retained-usage",
            "state": stateName,
            "steps": steps,
            "plugin.id": plugin.manifest.id.rawValue,
            "plugin.name": plugin.manifest.name,
            "plugin.topLevel": plugin.manifest.topLevel,
            "plugin.file": plugin.fileURL.lastPathComponent,
            "plugin.config": pluginConfig,
            "snapshot.present": snapshot != nil,
            "snapshot.primaryUsedPercent": snapshot?.primary?.usedPercent ?? -1,
            "snapshot.primaryWindowMinutes": snapshot?.primary?.windowMinutes ?? -1,
            "snapshot.secondaryPresent": snapshot?.secondary != nil,
            "snapshot.updatedAt": snapshot.map { ISO8601DateFormatter().string(from: $0.updatedAt) } ?? "nil",
            "snapshot.updatedAtRelative": snapshot.map { $0.updatedAt.relativeDescription() } ?? "nil",
            "error.text": error ?? "nil",
            "card.usageState": content.usage.rawValue,
            "card.isStale": content.isStale,
            "card.showsUsageRows": content.showsUsageRows,
            "card.errorText": observedErrorText,
            "card.lastKnownText": lastKnownText,
            "card.placeholderText": content.placeholderText ?? "nil",
            "card.isRefreshing": content.isRefreshing,
            "card.fingerprint": UserPluginMenuCardContent.fingerprint(snapshot: snapshot, error: error),
            "lastKnownUsagePresentation.message": lastKnownMessage,
            "menu.userPluginsForMenu.nonMerged": menuPluginIDs,
            "store.snapshotPresent": store.snapshots[pluginID] != nil,
            "store.errorPresent": store.errors[pluginID] != nil,
            "store.isRefreshing": store.refreshingProviders.contains(pluginID),
            "settings.isPluginEnabled": settings.isPluginEnabled(pluginID),
            "settings.selectedMenuProvider": settings.selectedMenuProvider?.rawValue ?? "nil",
            "settings.refreshFrequency": settings.refreshFrequency.rawValue,
            "registry.pluginIDs": registryIDs,
            "statusItem.debug": statusItem,
            "app.version": info["CFBundleShortVersionString"] as? String ?? "",
            "app.build": info["CFBundleVersion"] as? String ?? "",
            "app.gitCommit": info["CodexGitCommit"] as? String ?? "",
            "app.bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
            "app.bundlePath": Bundle.main.bundlePath,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        let runtimeEvidence = [
            "state=\(stateName)",
            "steps=\(steps)",
            "snapshot.present=\(snapshot != nil) "
                + "snapshot.primaryUsedPercent=\(snapshot?.primary?.usedPercent ?? -1) "
                + "snapshot.updatedAtRelative=\(snapshot.map { $0.updatedAt.relativeDescription() } ?? "nil")",
            "error.text=\(error ?? "nil")",
            "card.usageState=\(content.usage.rawValue) card.isStale=\(content.isStale) "
                + "card.showsUsageRows=\(content.showsUsageRows)",
            "card.errorText=\(observedErrorText)",
            "card.lastKnownText=\(lastKnownText)",
            "card.placeholderText=\(content.placeholderText ?? "nil")",
            "menu.userPluginsForMenu.nonMerged=\(menuPluginIDs)",
            "statusItem.debug=\(statusItem)",
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
                    to: directory.appendingPathComponent("runtime-evidence-\(stateName).txt"),
                    atomically: true,
                    encoding: .utf8)
        } catch {
            self.log("failed to write runtime evidence: \(error)")
        }
        self.writeMarker(directory: directory, state: stateName, payload: payload)

        self.log("opening the real status-item menu")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            appDelegate._proof_openStatusItemMenu()
        }
    }

    private static func writeServerMode(_ mode: String, directory: URL) {
        do {
            try "\(mode)\n".write(
                to: directory.appendingPathComponent("server_mode"),
                atomically: true,
                encoding: .utf8)
        } catch {
            self.log("failed to write server mode: \(error)")
        }
    }

    private static func writeMarker(directory: URL, state: String, payload: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            try data.write(
                to: directory.appendingPathComponent("marker-state-\(state).json"),
                options: [.atomic])
            try data.write(to: directory.appendingPathComponent("marker.json"), options: [.atomic])
            self.log("wrote marker \(directory.appendingPathComponent("marker-state-\(state).json").path)")
        } catch {
            self.log("failed to write marker: \(error)")
        }
    }

    private static func log(_ message: String) {
        FileHandle.standardOutput.write(Data("[proof-harness] \(message)\n".utf8))
    }
}
#endif
