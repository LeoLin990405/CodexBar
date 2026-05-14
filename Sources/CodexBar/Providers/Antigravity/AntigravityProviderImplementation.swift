import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct AntigravityProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .antigravity
    let supportsLoginFlow: Bool = true

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.antigravityUsageDataSource
        _ = settings.tokenAccountsData(for: .antigravity)
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.antigravityUsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.antigravityUsageDataSource {
        case .auto: .auto
        case .oauth: .oauth
        case .cli: .cli
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.antigravityUsageDataSource.rawValue },
            set: { raw in
                context.settings.antigravityUsageDataSource = AntigravityUsageDataSource(rawValue: raw) ?? .auto
            })
        let usageOptions = AntigravityUsageDataSource.allCases.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }
        return [
            ProviderSettingsPickerDescriptor(
                id: "antigravity-usage-source",
                title: "Usage source",
                subtitle: "Auto uses the local IDE API first, then Google OAuth when the IDE is closed.",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.antigravityUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .antigravity)
                    return label == "auto" ? nil : label
                }),
        ]
    }

    @MainActor
    func settingsActions(context: ProviderSettingsContext) -> [ProviderSettingsActionsDescriptor] {
        let accountCount = context.settings.tokenAccounts(for: .antigravity).count
        let loginTitle = accountCount > 0 ? "添加 Google 账户" : "使用 Google 登录"
        let subtitle = "保存每个已登录的 Google 账户以快速切换 Antigravity。"
            + "优先使用 Antigravity.app OAuth，也可通过 ANTIGRAVITY_OAUTH_CLIENT_ID 和 ANTIGRAVITY_OAUTH_CLIENT_SECRET 覆盖。"
        return [
            ProviderSettingsActionsDescriptor(
                id: "antigravity-oauth",
                title: "Google OAuth",
                subtitle: subtitle,
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "antigravity-oauth-login",
                        title: loginTitle,
                        style: .bordered,
                        isVisible: nil,
                        perform: {
                            await context.runLoginFlow()
                        }),
                ],
                isVisible: nil),
        ]
    }

    func detectVersion(context _: ProviderVersionContext) async -> String? {
        await AntigravityStatusProbe.detectVersion()
    }

    @MainActor
    func appendUsageMenuEntries(context _: ProviderMenuUsageContext, entries _: inout [ProviderMenuEntry]) {}

    @MainActor
    func loginMenuAction(context _: ProviderMenuLoginContext) -> (label: String, action: MenuDescriptor.MenuAction)? {
        ("添加账户…", .switchAccount(.antigravity))
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runAntigravityLoginFlow()
        return false
    }
}
