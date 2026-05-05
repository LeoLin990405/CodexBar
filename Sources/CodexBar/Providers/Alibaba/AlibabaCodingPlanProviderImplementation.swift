import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct AlibabaCodingPlanProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .alibaba

    @MainActor
    func presentation(context _: ProviderPresentationContext) -> ProviderPresentation {
        ProviderPresentation { context in
            context.store.sourceLabel(for: context.provider)
        }
    }

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.alibabaCodingPlanAPIToken
        _ = settings.alibabaCodingPlanCookieSource
        _ = settings.alibabaCodingPlanCookieHeader
        _ = settings.alibabaCodingPlanAPIRegion
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        _ = context
        return .alibaba(context.settings.alibabaCodingPlanSettingsSnapshot())
    }

    @MainActor
    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        let binding = Binding(
            get: { context.settings.alibabaCodingPlanAPIRegion.rawValue },
            set: { raw in
                context.settings
                    .alibabaCodingPlanAPIRegion = AlibabaCodingPlanAPIRegion(rawValue: raw) ?? .international
            })
        let options = AlibabaCodingPlanAPIRegion.allCases.map {
            ProviderSettingsPickerOption(id: $0.rawValue, title: $0.displayName)
        }

        let cookieBinding = Binding(
            get: { context.settings.alibabaCodingPlanCookieSource.rawValue },
            set: { raw in
                context.settings.alibabaCodingPlanCookieSource = ProviderCookieSource(rawValue: raw) ?? .auto
            })
        let cookieOptions = ProviderCookieSourceUI.options(
            allowsOff: false,
            keychainDisabled: context.settings.debugDisableKeychainAccess)
        let cookieSubtitle: () -> String? = {
            ProviderCookieSourceUI.subtitle(
                source: context.settings.alibabaCodingPlanCookieSource,
                keychainDisabled: context.settings.debugDisableKeychainAccess,
                auto: "自动导入 Model Studio/百炼的浏览器 Cookie。",
                manual: "粘贴来自 modelstudio.console.alibabacloud.com 的 Cookie header。",
                off: "Alibaba Cookie 已禁用。")
        }

        return [
            ProviderSettingsPickerDescriptor(
                id: "alibaba-coding-plan-cookie-source",
                title: "Cookie 来源",
                subtitle: "自动导入 Model Studio/百炼的浏览器 Cookie。",
                dynamicSubtitle: cookieSubtitle,
                binding: cookieBinding,
                options: cookieOptions,
                isVisible: nil,
                onChange: nil,
                trailingText: {
                    guard let entry = CookieHeaderCache.load(provider: .alibaba) else { return nil }
                    let when = entry.storedAt.relativeDescription()
                    return "已缓存：\(entry.sourceLabel) • \(when)"
                }),
            ProviderSettingsPickerDescriptor(
                id: "alibaba-coding-plan-region",
                title: "网关区域",
                subtitle: "获取额度时使用国际版或中国大陆控制台网关。",
                binding: binding,
                options: options,
                isVisible: nil,
                onChange: nil),
        ]
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "alibaba-coding-plan-api-key",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。粘贴来自 Model Studio 的 Coding Plan API key。",
                kind: .secure,
                placeholder: "cpk-...",
                binding: context.stringBinding(\.alibabaCodingPlanAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "alibaba-coding-plan-open-dashboard",
                        title: "打开 Coding Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(context.settings.alibabaCodingPlanAPIRegion.dashboardURL)
                        }),
                ],
                isVisible: nil,
                onActivate: { context.settings.ensureAlibabaCodingPlanAPITokenLoaded() }),
            ProviderSettingsFieldDescriptor(
                id: "alibaba-coding-plan-cookie",
                title: "Cookie header",
                subtitle: "",
                kind: .secure,
                placeholder: "Cookie: ...",
                binding: context.stringBinding(\.alibabaCodingPlanCookieHeader),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "alibaba-coding-plan-open-dashboard-cookie",
                        title: "打开 Coding Plan",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            NSWorkspace.shared.open(context.settings.alibabaCodingPlanAPIRegion.dashboardURL)
                        }),
                ],
                isVisible: {
                    context.settings.alibabaCodingPlanCookieSource == .manual
                },
                onActivate: nil),
        ]
    }
}
