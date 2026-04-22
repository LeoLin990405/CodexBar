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
                subtitle: "Stored in ~/.codexbar/config.json. Get your API key from the Zenmux "
                    + "dashboard.",
                kind: .secure,
                placeholder: "sk-ss-v1-... or sk-ai-v1-...",
                binding: context.stringBinding(\.zenmuxAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "zenmux-open-dashboard",
                        title: "Open Zenmux Dashboard",
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
