import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct ZenmuxProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .zenmux

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.zenmuxAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "zenmux-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。可在 Zenmux 仪表盘获取 API key。",
                kind: .secure,
                placeholder: "sk-ss-v1-... 或 sk-ai-v1-...",
                binding: context.stringBinding(\.zenmuxAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "zenmux-open-dashboard",
                        title: "打开 Zenmux 仪表盘",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://zenmux.ai/") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
