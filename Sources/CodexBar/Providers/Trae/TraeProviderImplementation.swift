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
                title: "Status",
                subtitle: "Trae is ByteDance's free AI IDE. CodexBar detects whether Trae is running "
                    + "on this machine.",
                kind: .plain,
                placeholder: "",
                binding: context.stringBinding(\.traeInfo),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "trae-open-website",
                        title: "Open Trae Website",
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
