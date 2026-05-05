import AppKit
import CodexBarCore
import Foundation

@MainActor
extension StatusItemController {
    func runVertexAILoginFlow() async {
        // Show alert with instructions
        let alert = NSAlert()
        alert.messageText = "Vertex AI 登录"
        alert.informativeText = """
        要使用 Vertex AI 跟踪，需要先通过 Google Cloud 认证。

        1. 打开终端
        2. 运行：gcloud auth application-default login
        3. 按浏览器提示完成登录
        4. 设置项目：gcloud config set project PROJECT_ID

        现在要打开终端吗？
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开终端")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            Self.openTerminalWithGcloudCommand()
        }

        // Refresh after user may have logged in
        self.loginPhase = .idle
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            await self.store.refresh()
        }
    }

    private static func openTerminalWithGcloudCommand() {
        let script = """
        tell application "Terminal"
            activate
            do script "gcloud auth application-default login --scopes=openid,https://www.googleapis.com/auth/userinfo.email,https://www.googleapis.com/auth/cloud-platform"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                CodexBarLog.logger(LogCategories.terminal).error(
                    "打开终端失败",
                    metadata: ["error": String(describing: error)])
            }
        }
    }
}
