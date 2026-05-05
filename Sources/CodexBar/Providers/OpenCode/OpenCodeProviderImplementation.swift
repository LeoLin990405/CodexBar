import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct OpenCodeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .opencode

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.opencodeCookieSource
        _ = settings.opencodeCookieHeader
        _ = settings.opencodeWorkspaceID
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .opencode(context.settings.opencodeSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.opencodeCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.opencodeCookieSource != .manual {
            settings.opencodeCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.opencodeCookieSource.rawValue },
            set: { raw in
                context.settings.opencodeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.opencodeCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入 opencode.ai 的浏览器 Cookie。",
                manual: "粘贴从账单页面捕获的 Cookie header。",
                off: "OpenCode Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "opencode-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入 opencode.ai 的浏览器 Cookie。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    OpenCodeProviderUI.cachedCookieTrailingText(
                        provider: .opencode,
                        cookieSource: context.settings.opencodeCookieSource)
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "opencode-workspace-id",
                title: "工作区 ID",
                subtitle: "工作区查找失败时可选填此覆盖值。",
                kind: .plain,
                placeholder: "wrk_…",
                binding: context.stringBinding(\.opencodeWorkspaceID),
                actions: [],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
