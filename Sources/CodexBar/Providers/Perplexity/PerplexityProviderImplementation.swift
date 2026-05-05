import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct PerplexityProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .perplexity
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { _ in "web" }
    }

    @MainActor
    func runLoginFlow(context _: ProviderLoginContext) async -> Bool {
        if let url = URL(string: "https://www.perplexity.ai/") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.perplexityCookieSource
        _ = settings.perplexityManualCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .perplexity(context.settings.perplexitySettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.perplexityCookieSource.rawValue },
            set: { raw in
                context.settings.perplexityCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let options = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let subtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.perplexityCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器会话 Cookie。",
                manual: "粘贴完整 Cookie header 或 __Secure-next-auth.session-token 值。",
                off: "Perplexity Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "perplexity-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入浏览器会话 Cookie。",
                dynamicSubtitle: subtitle,
                binding: cookieBinding,
                options: options,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "perplexity-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: \u{2026}\n\n或粘贴 __Secure-next-auth.session-token 值",
                binding: context.stringBinding(\.perplexityManualCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "perplexity-open-usage",
                        title: "打开用量页面",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://www.perplexity.ai/account/usage") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.perplexityCookieSource == .manual },
                onActivate: nil),
        ]
    }
}
