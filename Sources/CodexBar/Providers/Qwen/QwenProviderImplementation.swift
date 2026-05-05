import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct QwenProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .qwen

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.qwenAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "qwen-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。可在阿里云百炼/千问控制台（DashScope）获取 API key。",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.qwenAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "qwen-open-dashboard",
                        title: "打开百炼控制台",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://bailian.console.aliyun.com/") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
