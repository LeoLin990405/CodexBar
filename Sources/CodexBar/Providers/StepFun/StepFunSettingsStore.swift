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
}
