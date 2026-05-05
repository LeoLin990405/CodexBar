import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct AigoCodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .aigocode

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.aigocodeAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "aigocode-api-token",
                title: "API key",
                subtitle: "使用网页仪表盘模式时可不填。"
                    + "保存在 ~/.codexbar/config.json。",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.aigocodeAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "aigocode-open-dashboard",
                        title: "打开 AigoCode 仪表盘",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.aigocode.com/dashboard/console") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
