import Foundation

public enum ProviderCookieSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case auto
    case manual
    case off

    public var id: String {
        self.rawValue
    }

    public var displayName: String {
        switch self {
        case .auto: "自动"
        case .manual: "手动"
        case .off: "关闭"
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .off: false
        case .auto, .manual: true
        }
    }
}
