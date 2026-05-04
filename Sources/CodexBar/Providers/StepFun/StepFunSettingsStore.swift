import CodexBarCore
import Foundation

extension SettingsStore {
    var stepfunAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .stepfun)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .stepfun) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .stepfun, field: "apiKey", value: newValue)
        }
    }

    var stepfunCookieSource: ProviderCookieSource {
        get { self.resolvedCookieSource(provider: .stepfun, fallback: .auto) }
        set {
            self.updateProviderConfig(provider: .stepfun) { entry in
                entry.cookieSource = newValue
            }
            self.logProviderModeChange(provider: .stepfun, field: "cookieSource", value: newValue.rawValue)
        }
    }
}

extension SettingsStore {
    func stepfunSettingsSnapshot(tokenOverride: TokenAccountOverride?) -> ProviderSettingsSnapshot
    .StepFunProviderSettings {
        _ = tokenOverride
        return ProviderSettingsSnapshot.StepFunProviderSettings(
            cookieSource: self.stepfunCookieSource,
            manualCookieHeader: "")
    }
}
