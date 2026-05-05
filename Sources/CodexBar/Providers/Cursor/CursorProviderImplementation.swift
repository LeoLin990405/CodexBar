import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct CursorProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .cursor
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.cursorCookieSource
        _ = settings.cursorCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .cursor(context.settings.cursorSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.cursorCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.cursorCookieSource != .manual {
            settings.cursorCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.cursorCookieSource.rawValue },
            set: { raw in
                context.settings.cursorCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.cursorCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie 或已保存会话。",
                manual: "粘贴来自 cursor.com 请求的 Cookie header。",
                off: "Cursor Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "cursor-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入浏览器 Cookie 或已保存会话。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .cursor) else { return nil }
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
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runCursorLoginFlow()
        return true
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        guard let cost = context.snapshot?.providerCost, cost.currencyCode != "Quota" else { return }
        let used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
        if cost.limit > 0 {
            let limitStr = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
            entries.append(.text("On-Demand: \(used) / \(limitStr)", .primary))
        } else {
            entries.append(.text("On-Demand: \(used)", .primary))
        }
    }
}
