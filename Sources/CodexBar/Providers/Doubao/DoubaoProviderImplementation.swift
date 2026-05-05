import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct DoubaoProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .doubao

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.doubaoAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "doubao-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。可在火山引擎 Ark 控制台获取 API key。",
                kind: .secure,
                placeholder: "ark-...",
                binding: context.stringBinding(\.doubaoAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "doubao-open-dashboard",
                        title: "打开火山引擎 Ark 控制台",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://console.volcengine.com/ark/") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
