import Foundation

public enum KimiAPIError: LocalizedError, Sendable, Equatable {
    case missingToken
    case invalidToken
    case invalidRequest(String)
    case networkError(String)
    case apiError(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "缺少 Kimi auth token。请添加来自 Kimi 控制台的 JWT token。"
        case .invalidToken:
            "Kimi auth token 无效或已过期。请刷新 token。"
        case let .invalidRequest(message):
            "请求无效：\(message)"
        case let .networkError(message):
            "Kimi 网络错误：\(message)"
        case let .apiError(message):
            "Kimi API 错误：\(message)"
        case let .parseFailed(message):
            "解析 Kimi 用量数据失败：\(message)"
        }
    }
}
