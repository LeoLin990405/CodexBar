import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct KimiK2ProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .kimik2

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.kimiK2APIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "kimi-k2-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。可在 kimi-k2.ai 生成。",
                kind: .secure,
                placeholder: "粘贴 API key…",
                binding: context.stringBinding(\.kimiK2APIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "kimi-k2-open-api-keys",
                        title: "打开 API Keys",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://kimi-k2.ai/user-center/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: { context.settings.ensureKimiK2APITokenLoaded() }),
        ]
    }
}
