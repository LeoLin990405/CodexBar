import CodexBarCore
import CodexBarMacroSupport
import Foundation
import SwiftUI

@ProviderImplementationRegistration
struct KiroProviderImplementation: ProviderImplementation {
    let id: UsageProvider = .kiro

    func settingsPickers(context: ProviderSettingsContext) -> [ProviderSettingsPickerDescriptor] {
        [
            ProviderSettingsPickerDescriptor(
                id: "kiroMenuBarDisplay",
                title: "Kiro 菜单栏显示值",
                subtitle: "选择在菜单栏图标旁显示 Kiro Credits、百分比或两者。",
                binding: Binding(
                    get: { context.settings.kiroMenuBarDisplayMode.rawValue },
                    set: { rawValue in
                        guard let mode = KiroMenuBarDisplayMode(rawValue: rawValue) else { return }
                        context.settings.kiroMenuBarDisplayMode = mode
                    }),
                options: KiroMenuBarDisplayMode.allCases.map {
                    ProviderSettingsPickerOption(id: $0.rawValue, title: $0.label)
                },
                isVisible: { true },
                onChange: nil),
        ]
    }
}
