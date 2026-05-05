import AppKit
import CodexBarCore
import CodexBarMacroSupport
import Foundation

@ProviderImplementationRegistration
struct StepFunProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .stepfun

    @MainActor
    func observeSettings(_ settings: SettingsStore) {
        _ = settings.stepfunAPIToken
        _ = settings.stepfunCookieSource
    }

    @MainActor
    func settingsSnapshot(context: ProviderSettingsSnapshotContext) -> ProviderSettingsSnapshotContribution? {
        .stepfun(context.settings.stepfunSettingsSnapshot(tokenOverride: context.tokenOverride))
    }

    @MainActor
    func settingsFields(context: ProviderSettingsContext) -> [ProviderSettingsFieldDescriptor] {
        [
            ProviderSettingsFieldDescriptor(
                id: "stepfun-api-token",
                title: "API key",
                subtitle: "保存在 ~/.codexbar/config.json。可在阶跃星辰平台获取 API key。",
                kind: .secure,
                placeholder: "sf-...",
                binding: context.stringBinding(\.stepfunAPIToken),
                actions: [
                    ProviderSettingsActionDescriptor(
                        id: "stepfun-open-dashboard",
                        title: "打开阶跃星辰平台",
                        style: .link,
                        isVisible: nil,
                        perform: {
                            if let url = URL(string: "https://platform.stepfun.com/plan-subscribe") {
                                NSWorkspace.shared.open(url)
                            }
                        }),
                ],
                isVisible: nil,
                onActivate: nil),
        ]
    }
}
