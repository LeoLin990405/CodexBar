import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct AugmentProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .augment

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.augmentCookieSource
        _ = settings.augmentCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .augment(context.settings.augmentSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.augmentCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.augmentCookieSource != .manual {
            settings.augmentCookieSource = .manual
        }
    }

    func makeRuntime() -> (any ProviderRuntime)? {
        AugmentProviderRuntime()
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.augmentCookieSource.rawValue },
            set: { raw in
                context.settings.augmentCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.augmentCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie。",
                manual: "粘贴来自 Augment 仪表盘的 Cookie header 或 cURL 抓取内容。",
                off: "Augment Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "augment-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入浏览器 Cookie。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .augment) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "已缓存：\(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        _ = context
        return []
    }

    @MainActor
    func appendActionMenuEntries(context: ProviderMenuActionContext, entries: inout [ProviderMenuEntry]) {
        entries.append(.action("刷新会话", .refreshAugmentSession))

        if let error = context.store.error(for: .augment) {
            if error.contains("session has expired") ||
                error.contains("No Augment session cookie found")
            {
                entries.append(.action(
                    "打开 Augment（退出并重新登录）",
                    .loginToProvider(url: "https://app.augmentcode.com")))
            }
        }
    }
}
