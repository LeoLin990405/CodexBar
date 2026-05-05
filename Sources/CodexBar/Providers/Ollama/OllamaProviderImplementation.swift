import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct OllamaProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .ollama

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.ollamaCookieSource
        _ = settings.ollamaCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .ollama(context.settings.ollamaSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.ollamaCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.ollamaCookieSource != .manual {
            settings.ollamaCookieSource = .manual
        }
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let cookieBinding = Binding(
            get: { context.settings.ollamaCookieSource.rawValue },
            set: { raw in
                context.settings.ollamaCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.ollamaCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie。",
                manual: "粘贴来自 Ollama 设置的 Cookie header 或 cURL 抓取内容。",
                off: "Ollama Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "ollama-cookie-source",
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
                id: "ollama-cookie",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.ollamaCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "ollama-open-settings",
                        title: "打开 Ollama 设置",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://ollama.com/settings") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: { context.settings.ollamaCookieSource == .manual },
                onActivate: { context.settings.ensureOllamaCookieLoaded() }),
        ]
    }
}
