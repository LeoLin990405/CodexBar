import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct OpenRouterProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .openrouter

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.openRouterAPIToken
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        _ = context
        return nil
    }

    @MainActor
    func isAvailable(context: ProviderAvailabilityContext) -> Bool {
        if OpenRouterSettingsReader.apiToken(environment: context.environment) != nil {
            return true
        }
        return !context.settings.openRouterAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    func settingsPickers(context _: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        []
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "openrouter-api-key",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。"
                    + "请从 openrouter.ai/settings/keys 获取 key，并在那里设置 key 消费上限，"
                    + "以启用 API key 额度跟踪。",
                kind: .secure,
                placeholder: "sk-or-v1-...",
                binding: context.stringBinding(\.openRouterAPIToken),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
