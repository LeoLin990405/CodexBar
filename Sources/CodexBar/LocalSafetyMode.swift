import CodexBarCore
import Foundation

enum LocalSafetyMode {
    static var isEnabled: Bool {
        !self.isRunningTests
    }

    static let launchAtLogin = false
    static let debugDisableKeychainAccess = true
    static let claudeOAuthKeychainPromptMode: ClaudeOAuthKeychainPromptMode = .never
    static let appLanguage = "zh-Hans"

    private static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil { return true }
        if env["TESTING_LIBRARY_VERSION"] != nil { return true }
        if env["SWIFT_TESTING"] != nil { return true }
        return NSClassFromString("XCTestCase") != nil
    }

    static func apply(to userDefaults: UserDefaults, sharedDefaults: UserDefaults?) {
        guard self.isEnabled else { return }
        userDefaults.set(self.launchAtLogin, forKey: "launchAtLogin")
        userDefaults.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
        userDefaults.set(
            self.claudeOAuthKeychainPromptMode.rawValue,
            forKey: "claudeOAuthKeychainPromptMode")
        userDefaults.set(self.appLanguage, forKey: "appLanguage")
        sharedDefaults?.set(self.debugDisableKeychainAccess, forKey: "debugDisableKeychainAccess")
    }
}
