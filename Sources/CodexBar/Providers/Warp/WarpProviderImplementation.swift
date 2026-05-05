import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct WarpProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .warp

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.warpAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "warp-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。在 Warp 中打开 Settings > Platform > API Keys，然后创建一个 key。",
                kind: .secure,
                placeholder: "wk-...",
                binding: context.stringBinding(\.warpAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "warp-open-api-keys",
                        title: "打开 Warp API Key 指南",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://docs.warp.dev/reference/cli/api-keys") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
