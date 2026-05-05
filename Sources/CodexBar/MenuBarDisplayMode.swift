import Foundation

/// Controls what the menu bar displays when brand icon mode is enabled.
enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case percent
    case pace
    case both

    var id: String {
        self.rawValue
    }

    var label: String {
        switch self {
        case .percent: "百分比"
        case .pace: "节奏"
        case .both: "两者"
        }
    }

    var description: String {
        switch self {
        case .percent: "显示剩余/已用百分比（例如 45%）"
        case .pace: "显示节奏指示（例如 +5%）"
        case .both: "同时显示百分比和节奏（例如 45% · +5%）"
        }
    }
}
