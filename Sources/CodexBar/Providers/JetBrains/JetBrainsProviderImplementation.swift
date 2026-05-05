import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct JetBrainsProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .jetbrains

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        _ = context
        return .jetbrains(context.settings.jetbrainsSettingsSnapshot())
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let detectedIDEs = JetBrainsIDEDetector.detectInstalledIDEs(includeMissingQuota: true)
        guard !detectedIDEs.isEmpty else { return [] }

        var options: [ProviderSettingsPickerOption] = [
            ProviderSettingsPickerOption(id: "", title: "自动检测"),
        ]
        for ide in detectedIDEs {
            options.append(ProviderSettingsPickerOption(id: ide.basePath, title: ide.displayName))
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "jetbrains.ide",
                title: "JetBrains IDE",
                subtitle: "选择要监控的 IDE",
                binding: context.stringBinding(\.jetbrainsIDEBasePath),
                options: options,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    if context.settings.jetbrainsIDEBasePath.isEmpty {
                        if let latest = JetBrainsIDEDetector.detectLatestIDE() {
                            return latest.displayName
                        }
                    }
                    return nil
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "jetbrains.customPath",
                title: "自定义路径",
                subtitle: "用自定义 IDE 基础路径覆盖自动检测",
                kind: .plain,
                placeholder: "~/Library/Application Support/JetBrains/IntelliJIdea2024.3",
                binding: context.stringBinding(\.jetbrainsIDEBasePath),
                actions: [],
                isVisible: {
                    let detectedIDEs = JetBrainsIDEDetector.detectInstalledIDEs()
                    return detectedIDEs.isEmpty || !context.settings.jetbrainsIDEBasePath.isEmpty
                },
                onActivate: nil),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runJetBrainsLoginFlow()
        return false
    }
}
