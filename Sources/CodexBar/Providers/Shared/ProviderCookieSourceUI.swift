import CodexBarCore

enum ProviderCookieSourceUI {
    static let keychainDisabledPrefix =
        "已在“高级”中禁用钥匙串访问，因此无法导入浏览器 Cookie。"

    static func options(allowsOff: Bool, keychainDisabled: Bool) -> [ProviderSettingsPickerOption] {
        var options: [ProviderSettingsPickerOption] = []
        if !keychainDisabled {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.auto.rawValue,
                title: ProviderCookieSource.auto.displayName))
        }
        options.append(ProviderSettingsPickerOption(
            id: ProviderCookieSource.manual.rawValue,
            title: ProviderCookieSource.manual.displayName))
        if allowsOff {
            options.append(ProviderSettingsPickerOption(
                id: ProviderCookieSource.off.rawValue,
                title: ProviderCookieSource.off.displayName))
        }
        return options
    }

    static func subtitle(
        source: ProviderCookieSource,
        keychainDisabled: Bool,
        auto: String,
        manual: String,
        off: String) -> String
    {
        if keychainDisabled {
            return source == .off ? off : "\(self.keychainDisabledPrefix) \(manual)"
        }
        switch source {
        case .auto:
            return auto
        case .manual:
            return manual
        case .off:
            return off
        }
    }
}
