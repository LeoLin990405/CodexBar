import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct AmpProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .amp

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.ampCookieSource
        _ = settings.ampCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .amp(context.settings.ampSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.ampCookieSource.rawValue },
            set: { raw in
                context.settings.ampCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.ampCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie。",
                manual: "粘贴来自 Amp 设置的 Cookie header 或 cURL 抓取内容。",
                off: "Amp Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "amp-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入浏览器 Cookie。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "amp-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.ampCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "amp-open-settings",
                        title: "打开 Amp 设置",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://ampcode.com/settings") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.ampCookieSource == .manual },
                onActivate: { context.settings.ensureAmpCookieLoaded() }),
        ]
    }
}
