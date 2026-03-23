import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct StepFunProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .stepfun

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.stepfunAPIToken
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "stepfun-api-token",
                title: "API key",
                subtitle: "Stored in ~/.codexbar/config.json. Get your API key from the StepFun platform.",
                kind: .secure,
                placeholder: "sf-...",
                binding: context.stringBinding(\.stepfunAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "stepfun-open-dashboard",
                        title: "Open StepFun Platform",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://platform.stepfun.com/plan-subscribe") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
