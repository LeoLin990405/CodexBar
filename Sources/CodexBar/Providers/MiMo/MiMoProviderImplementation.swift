import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct MiMoProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .mimo
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.miMoCookieSource
        _ = settings.miMoCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .mimo(context.settings.miMoSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.miMoCookieSource.rawValue },
            set: { raw in
                context.settings.miMoCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.miMoCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入“小米 Mimo”的 Chrome 浏览器 Cookie。",
                manual: "粘贴来自 platform.xiaomimimo.com 的 Cookie header。",
                off: "小米 Mimo Cookie 已关闭。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "mimo-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入“小米 Mimo”的 Chrome 浏览器 Cookie。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .mimo) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "已缓存：\(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "mimo-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: ...",
                binding: context.stringBinding(\.miMoCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "mimo-open-balance",
                        title: "打开小米 Mimo 余额",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            guard let url = URL(string: "https://platform.xiaomimimo.com/#/console/balance") else {
                                return
                            }
                            NSWorkspace.shared.open(url)
                        }),
                ],
                isVisible: { context.settings.miMoCookieSource == .manual },
                onActivate: { context.settings.ensureMiMoCookieLoaded() }),
        ]
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        let loginURL = "https://platform.xiaomimimo.com/api/v1/genLoginUrl?currentPath=%2F%23%2Fconsole%2Fbalance"
        guard let url = URL(string: loginURL) else {
            return false
        }
        NSWorkspace.shared.open(url)
        return false
    }
}
