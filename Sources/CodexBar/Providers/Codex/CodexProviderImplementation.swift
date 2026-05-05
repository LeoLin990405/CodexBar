import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct CodexProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .codex
    let supportsLoginFlow: Bool = true

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.version(for: context.provider) ?? "未检测到"
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.codexUsageDataSource
        _ = settings.codexCookieSource
        _ = settings.codexCookieHeader
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .codex(context.settings.codexSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func defaultSourceLabel(context: ProviderSourceLabelContext) -> String? {
        context.settings.codexUsageDataSource.rawValue
    }

    @MainActor
    func decorateSourceLabel(context: ProviderSourceLabelContext, baseLabel: String) -> String {
        if context.settings.codexCookieSource.isEnabled,
           context.store.openAIDashboard != nil,
           !context.store.openAIDashboardRequiresLogin,
           !baseLabel.contains("openai-web")
        {
            return "\(baseLabel) + openai-web"
        }
        return baseLabel
    }

    @MainActor
    func sourceMode(context: ProviderSourceModeContext) -> ProviderSourceMode {
        switch context.settings.codexUsageDataSource {
        case .auto: .auto
        case .oauth: .oauth
        case .cli: .cli
        }
    }

    func makeRuntime() -> (any ProviderRuntime)? {
        CodexProviderRuntime()
    }

    @MainActor
    func settingsToggles(context: ProviderSettingsContext) -> [ProviderSettingsToggleDescriptor] {
        let extrasBinding = Binding(
            get: { context.settings.openAIWebAccessEnabled },
            set: { enabled in
                context.settings.openAIWebAccessEnabled = enabled
                Task { @MainActor in
                    await context.store.performRuntimeAction(
                        .openAIWebAccessToggled(enabled),
                        for: .codex)
                }
            })
        let batterySaverBinding = context.boolBinding(\.openAIWebBatterySaverEnabled)

        return [
            ProviderSettingsToggleDescriptor(
                id: "codex-historical-tracking",
                title: "历史跟踪",
                subtitle: "保存本地 Codex 用量历史（8 周），用于个性化节奏预测。",
                binding: context.boolBinding(\.historicalTrackingEnabled),
                statusText: nil,
                actions: [],
                isVisible: nil,
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil),
            ProviderSettingsToggleDescriptor(
                id: "codex-openai-web-extras",
                title: "OpenAI 网页增强",
                subtitle: [
                    "可选。",
                    "开启后通过 chatgpt.com 显示代码审查、用量明细和 Credits 历史。",
                ].joined(separator: " "),
                binding: extrasBinding,
                statusText: nil,
                actions: [],
                isVisible: nil,
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil),
            ProviderSettingsToggleDescriptor(
                id: "codex-openai-web-battery-saver",
                title: "省电模式",
                subtitle: [
                    "限制后台 chatgpt.com 刷新，减少耗电和网络占用。",
                    "仪表盘增强数据可能保持旧状态，直到你手动刷新。",
                ].joined(separator: " "),
                binding: batterySaverBinding,
                statusText: nil,
                actions: [],
                isVisible: { context.settings.openAIWebAccessEnabled },
                onChange: nil,
                onAppDidBecomeActive: nil,
                onAppearWhenEnabled: nil),
        ]
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let usageBinding = Binding(
            get: { context.settings.codexUsageDataSource.rawValue },
            set: { raw in
                context.settings.codexUsageDataSource = CodexUsageDataSource(rawValue: raw) ?? .auto
            })
        let cookieBinding = Binding(
            get: { context.settings.codexCookieSource.rawValue },
            set: { raw in
                context.settings.codexCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })

        let usageOptions = CodexUsageDataSource.allCases.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: true,
            keychainDisabled: context.settings.debugDisableKeychainAccess)

        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.codexCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入浏览器 Cookie，用于仪表盘增强数据。",
                manual: "粘贴来自 chatgpt.com 请求的 Cookie header。",
                off: "关闭 OpenAI 仪表盘 Cookie 使用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "codex-usage-source",
                title: "用量来源",
                subtitle: "自动模式会在首选来源失败后切换到下一个来源。",
                binding: usageBinding,
                options: usageOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard context.settings.codexUsageDataSource == .auto else { return nil }
                    let label = context.store.sourceLabel(for: .codex)
                    return label == "auto" ? nil : label
                }),
            ProviderSettingsPickerDescriptor(
                id: "codex-cookie-source",
                title: "OpenAI Cookie",
                subtitle: "自动导入浏览器 Cookie，用于仪表盘增强数据。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: { context.settings.openAIWebAccessEnabled },
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .codex) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "已缓存：\(entry.sourceLabel) • \(when)"
                }),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "codex-cookie-header",
                title: "",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: …",
                binding: context.stringBinding(\.codexCookieHeader),
                actions: [],
                isVisible: {
                    context.settings.codexCookieSource == .manual
                },
                onActivate: { context.settings.ensureCodexCookieLoaded() }),
        ]
    }

    @MainActor
    func appendUsageMenuEntries(context: ProviderMenuUsageContext, entries: inout [ProviderMenuEntry]) {
        guard context.settings.showOptionalCreditsAndExtraUsage,
              context.metadata.supportsCredits
        else { return }

        if let credits = context.store.credits {
            entries.append(.text("Credits: \(UsageFormatter.creditsString(from: credits.remaining))", .primary))
            if let latest = credits.events.first {
                entries.append(.text("Last spend: \(UsageFormatter.creditEventSummary(latest))", .secondary))
            }
        } else {
            let hint = context.store.userFacingLastCreditsError ?? context.metadata.creditsHint
            entries.append(.text(hint, .secondary))
        }
    }

    @MainActor
    func loginMenuAction(context _: ProviderMenuLoginContext)
        -> (label: String, action: MenuDescriptor.MenuAction)?
    {
        ("Add Account...", .addCodexAccount)
    }

    @MainActor
    func appendActionMenuEntries(context: ProviderMenuActionContext, entries: inout [ProviderMenuEntry]) {
        let projection = context.settings.codexVisibleAccountProjection
        guard !projection.visibleAccounts.isEmpty else { return }

        let isInteractionBlocked = context.codexAccountPromotionCoordinator?.isInteractionBlocked() ?? false

        let submenuItems = projection.visibleAccounts.map { account in
            let isChecked = account.id == projection.liveVisibleAccountID
            let isEnabled = !isInteractionBlocked &&
                !isChecked &&
                account.storedAccountID != nil
            let action = account.storedAccountID.map(MenuDescriptor.MenuAction.requestCodexSystemPromotion)
            return MenuDescriptor.SubmenuItem(
                title: account.displayName,
                action: action,
                isEnabled: isEnabled,
                isChecked: isChecked)
        }

        entries.append(.submenu(
            "System Account",
            MenuDescriptor.MenuActionSystemImage.systemAccount.rawValue,
            submenuItems))
    }

    @MainActor
    func runLoginFlow(context: ProviderLoginContext) async -> Bool {
        await context.controller.runCodexLoginFlow()
        return true
    }
}
