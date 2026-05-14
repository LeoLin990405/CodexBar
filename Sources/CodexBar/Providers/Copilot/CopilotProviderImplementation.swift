import AppKit
import CodexBarCore
import CodexBarMacroSupport
import SwiftUI

@ProviderImplementationRegistration
struct CopilotProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .copilot
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "github api" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.copilotAPIToken
        _ = settings.copilotEnterpriseHost
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .copilot(context.settings.copilotSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func loginMenuAction(context _: ProviderMenuLoginContext)
        -> (label: String, action: MenuDescriptor.MenuAction)?
    {
        ("Add Account...", .addProviderAccount(.copilot))
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "copilot-enterprise-host",
                title: "企业版主机",
                subtitle: "可选。输入您的 GitHub Enterprise 主机，例如 octocorp.ghe.com。留空则使用 github.com。",
                kind: .plain,
                placeholder: "github.com",
                binding: context.stringBinding(\.copilotEnterpriseHost),
                actions: [],
                isVisible: nil,
                onActivate: nil),
            ProviderSettingsFieldDescriptor(
                id: "copilot-add-account",
                title: "GitHub Login",
                subtitle: "Add accounts via GitHub OAuth Device Flow on the selected host.",
                kind: .plain,
                placeholder: nil,
                binding: .constant(""),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "copilot-add-account-action",
                        title: "Add Account",
                        style: .bordered,
                        isVisible: { true },
                        perform: {
                            await CopilotLoginFlow.run(settings: context.settings)
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await CopilotLoginFlow.run(settings: context.controller.settings)
        return true
    }
}
