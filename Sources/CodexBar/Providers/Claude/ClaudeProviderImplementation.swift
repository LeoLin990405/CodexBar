import CodexBarCore
import CodexBarMacroSupport
import SwiftUI

@ProviderImplementationRegistration
struct ClaudeProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .claude
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            var versionText = context.store.version(for: context.provider) ?? "未检测到"
            if let parenRange = versionText.range(of: "(") {
                versionText = versionText[..<parenRange.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            return "\(context.metadata.cliName) \(versionText)"
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.claudeUsageDataSource
        _ = settings.claudeCookieSource
        _ = settings.claudeCookieHeader
        _ = settings.claudeOAuthKeychainPromptMode
        _ = settings.claudeOAuthKeychainReadStrategy
        _ = settings.claudeWebExtrasEnabled
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .claude(context.settings.claudeSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func tokenAccountsVisibility(context: ProviderSettingsContext, support: TokenAccountSupport) -> Bool {
        guard support.requiresManualCookieSource else { return true }
        if !context.settings.tokenAccounts(for: context.provider).isEmpty { return true }
        return context.settings.claudeCookieSource == .manual
    }

    @MainActor
    func applyTokenAccountCookieSource(settings: SettingsStore) {
        if settings.claudeCookieSource != .manual {
            settings.claudeCookieSource = .manual
        }
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.claudeUsageDataSource.rawValue
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.claudeUsageDataSource {
        case .auto: .auto
        case .oauth: .oauth
        case .web: .web
        case .cli: .cli
        }
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        let subtitle = if context.settings.debugDisableKeychainAccess {
            "Inactive while \"Disable Keychain access\" is enabled in Advanced."
        } else {
            "Use /usr/bin/security to read Claude credentials and avoid CodexBar keychain prompts."
        }

        let promptFreeBinding = Binding(
            get: { context.settings.claudeOAuthPromptFreeCredentialsEnabled },
            set: { enabled in
                guard !context.settings.debugDisableKeychainAccess else { return }
                context.settings.claudeOAuthPromptFreeCredentialsEnabled = enabled
            })

        return [
            ProviderSettingsToggleDescriptor(
                id: "claude-oauth-prompt-free-credentials",
                title: "避免钥匙串弹窗",
                subtitle: subtitle,
                binding: promptFreeBinding,
                statusText: nil,
                actions: [],
                isVisible: nil,
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil),
        ]
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.claudeUsageDataSource.rawValue },
            set: { raw in
                context.settings.claudeUsageDataSource = ClaudeUsageDataSource(rawValue: raw) ?? .auto
            })
        let cookieBinding = Binding(
            get: { context.settings.claudeCookieSource.rawValue },
            set: { raw in
                context.settings.claudeCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let keychainPromptPolicyBinding = Binding(
            get: { context.settings.claudeOAuthKeychainPromptMode.rawValue },
            set: { raw in
                context.settings.claudeOAuthKeychainPromptMode = ClaudeOAuthKeychainPromptMode(rawValue: raw)
                    ?? .onlyOnUserAction
            })

        let usageOptions = ClaudeUsageDataSource.allCases.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let keychainPromptPolicyOptions: [ProviderSettingsPickerOption] = [
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.never.rawValue,
                title: "永不弹窗"),
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.onlyOnUserAction.rawValue,
                title: "仅用户操作时"),
            ProviderSettingsPickerOption(
                id: ClaudeOAuthKeychainPromptMode.always.rawValue,
                title: "始终允许弹窗"),
        ]
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.claudeCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie，用于 Web API。",
                manual: "粘贴来自 claude.ai 请求的 Cookie header。",
                off: "Claude Cookie 已关闭。")
        }
        let keychainPromptPolicySubtitle: () -> String? = {
            if context.settings.debugDisableKeychainAccess {
                return "已在“高级”中禁用全局钥匙串访问，因此此设置当前不生效。"
            }
            return "控制标准读取器启用时 Claude OAuth 的钥匙串弹窗策略。选择“永不弹窗”可能导致 OAuth 不可用；必要时请使用 Web/CLI。"
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "claude-usage-source",
                title: "用量来源",
                subtitle: "自动模式会在首选来源失败后切换到下一个来源。",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.claudeUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .claude)
                    return label == "auto" ? nil : label
                }),
            ProviderSettingsPickerDescriptor(
                id: "claude-keychain-prompt-policy",
                title: "钥匙串弹窗策略",
                subtitle: "仅适用于 Security.framework OAuth 钥匙串读取器。",
                dynamicSubtitle: keychainPromptPolicySubtitle,
                binding: keychainPromptPolicyBinding,
                options: keychainPromptPolicyOptions,
                isVisible: { context.settings.claudeOAuthKeychainReadStrategy == .securityFramework },
                isEnabled: { !context.settings.debugDisableKeychainAccess },
                onChange: nil),
            ProviderSettingsPickerDescriptor(
                id: "claude-cookie-source",
                title: "Claude Cookie",
                subtitle: "自动导入浏览器 Cookie，用于 Web API。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .claude) else { return nil }
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
        await context.controller.runClaudeLoginFlow()
        return true
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        if context.snapshot?.secondary == nil {
            entries.append(.text("Weekly usage unavailable for this account.", .secondary))
        }

        if let cost = context.snapshot?.providerCost,
           context.settings.showOptionalCreditsAndExtraUsage,
           cost.currencyCode != "Quota"
        {
            let used = UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode)
            let limit = UsageFormatter.currencyString(cost.limit, currencyCode: cost.currencyCode)
            entries.append(.text("Extra usage: \(used) / \(limit)", .primary))
        }
    }

    @MainActor
    func loginMenuAction(context: ProviderMenuLoginContext)
        -> (label: String, action: MenuDescriptor.MenuAction)?
    {
        guard self.shouldOpenTerminalForOAuthError(store: context.store) else { return nil }
        return ("打开终端", .openTerminal(command: "claude"))
    }

    @MainActor
    private func shouldOpenTerminalForOAuthError(store: UsageStore) -> Bool {
        guard store.error(for: .claude) != nil else { return false }
        let attempts = store.fetchAttempts(for: .claude)
        if attempts.contains(where: { $0.kind == .oauth && ($0.errorDescription?.isEmpty == false) }) {
            return true
        }
        if let error = store.error(for: .claude)?.lowercased(), error.contains("oauth") {
            return true
        }
        return false
    }
}
