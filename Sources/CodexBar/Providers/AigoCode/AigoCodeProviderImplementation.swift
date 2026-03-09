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
                subtitle: "Stored in ~/.codexbar/config.json. Get your API key from the AigoCode "
                    + "dashboard.",
                kind: .secure,
                placeholder: "sk-...",
                binding: context.stringBinding(\.aigocodeAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "aigocode-open-dashboard",
                        title: "Open AigoCode Dashboard",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.aigocode.com/") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
