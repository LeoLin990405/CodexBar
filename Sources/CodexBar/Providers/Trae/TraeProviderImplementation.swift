import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct TraeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .trae

    @MainActor
    func observeSettings(_ settings: SettingsStore) {}

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "trae-info",
                title: "状态",
                subtitle: "Trae 是字节跳动的免费 AI IDE。CodexBar 会检测这台机器上是否正在运行 Trae。",
                kind: .plain,
                placeholder: "",
                binding: context.stringBinding(\.traeInfo),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "trae-open-website",
                        title: "打开 Trae 官网",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.trae.ai") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
