import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct StepFunProviderImplementationTests {
    @Test
    func `settings UI uses TokenPlan language`() {
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "StepFunProviderImplementationTests-tokenplan"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let context = ProviderSettingsContext(
            provider: .stepfun,
            settings: settings,
            store: store,
            boolBinding: { _ in .constant(false) },
            stringBinding: { _ in .constant("") },
            statusText: { _ in nil },
            setStatusText: { _, _ in },
            lastAppActiveRunAt: { _ in nil },
            setLastAppActiveRunAt: { _, _ in },
            requestConfirmation: { _ in })
        let implementation = StepFunProviderImplementation()

        let picker = implementation.settingsPickers(context: context).first
        let fields = implementation.settingsFields(context: context)
        let manualField = fields.first { $0.id == "stepfun-token" }

        #expect(picker?.subtitle.contains("TokenPlan") == true)
        #expect(picker?.dynamicSubtitle?()?.contains("TokenPlan") == true)
        #expect(manualField?.title == "TokenPlan credential")
        #expect(manualField?.subtitle.contains("TokenPlan") == true)
        #expect(manualField?.placeholder?.contains("TokenPlan") == true)
        #expect(manualField?.actions.first?.title == "Open StepFun TokenPlan")
        #expect(manualField?.title.localizedCaseInsensitiveContains("Oasis-Token") == false)
        #expect(manualField?.subtitle.localizedCaseInsensitiveContains("Oasis-Token") == false)
        #expect(manualField?.placeholder?.localizedCaseInsensitiveContains("Oasis-Token") == false)
    }
}
