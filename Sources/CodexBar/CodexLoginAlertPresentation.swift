import Foundation

struct CodexLoginAlertInfo: Equatable {
    let title: String
    let message: String
}

enum CodexLoginAlertPresentation {
    static func alertInfo(for result: CodexLoginRunner.Result) -> CodexLoginAlertInfo? {
        switch result.outcome {
        case .success:
            return nil
        case .missingBinary:
            return CodexLoginAlertInfo(
                title: "未找到 Codex CLI",
                message: "请安装 Codex CLI（npm i -g @openai/codex）后重试。")
        case let .launchFailed(message):
            return CodexLoginAlertInfo(title: "无法启动 codex login", message: message)
        case .timedOut:
            return CodexLoginAlertInfo(
                title: "Codex 登录超时",
                message: self.trimmedOutput(result.output))
        case let .failed(status):
            let statusLine = "codex login 退出状态码为 \(status)。"
            let message = self.trimmedOutput(result.output.isEmpty ? statusLine : result.output)
            return CodexLoginAlertInfo(title: "Codex 登录失败", message: message)
        }
    }

    private static func trimmedOutput(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = 600
        if trimmed.isEmpty { return "未捕获到输出。" }
        if trimmed.count <= limit { return trimmed }
        let idx = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return "\(trimmed[..<idx])…"
    }
}
