import CodexBarCore
import Foundation

extension SettingsStore {
    var aigocodeAPIToken: String {
        get { self.configSnapshot.providerConfig(for: .aigocode)?.sanitizedAPIKey ?? "" }
        set {
            self.updateProviderConfig(provider: .aigocode) { entry in
                entry.apiKey = self.normalizedConfigValue(newValue)
            }
            self.logSecretUpdate(provider: .aigocode, field: "apiKey", value: newValue)
        }
    }
}
