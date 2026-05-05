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
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        _ = context
        return .copilot(context.settings.copilotSettingsSnapshot())
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "copilot-api-token",
                title: "GitHub 登录",
                subtitle: "需要通过 GitHub Device Flow 认证。",
                kind: .secure,
                placeholder: "通过下方按钮登录",
                binding: context.stringBinding(\.copilotAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "copilot-login",
                        title: "使用 GitHub 登录",
                        style: .bordered,
                        isVisible: { context.settings.copilotAPIToken.isEmpty },
                        perform: {
                            await CopilotLoginFlow.run(settings: context.settings)
                        }),
                    ProviderSettingsActionDescriptor(
                        id: "copilot-relogin",
                        title: "重新登录",
                        style: .link,
                        isVisible: { !context.settings.copilotAPIToken.isEmpty },
                        perform: {
                            await CopilotLoginFlow.run(settings: context.settings)
                        }),
                ],
                isVisible: nil,
                onActivate: { context.settings.ensureCopilotAPITokenLoaded() }),
        ]
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await CopilotLoginFlow.run(settings: context.controller.settings)
        return true
    }
}
