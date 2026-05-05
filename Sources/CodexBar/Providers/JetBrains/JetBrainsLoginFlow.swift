import CodexBarCore

@MainActor
extension StatusItemController {
    func runJetBrainsLoginFlow() async {
        self.loginPhase = .idle
        let detectedIDEs = JetBrainsIDEDetector.detectInstalledIDEs(includeMissingQuota: true)
        if detectedIDEs.isEmpty {
            let message = [
                "请安装已启用 AI Assistant 的 JetBrains IDE，然后刷新 CodexBar。",
                "也可以在设置里指定自定义路径。",
            ].joined(separator: " ")
            self.presentLoginAlert(
                title: "未检测到 JetBrains IDE",
                message: message)
        } else {
            let ideNames = detectedIDEs.prefix(3).map(\.displayName).joined(separator: ", ")
            let hasQuotaFile = !JetBrainsIDEDetector.detectInstalledIDEs().isEmpty
            let message = hasQuotaFile
                ? "已检测到：\(ideNames)。请在设置里选择要监控的 IDE，然后刷新 CodexBar。"
                : "已检测到：\(ideNames)。请先使用一次 AI Assistant 生成额度数据，然后刷新 CodexBar。"
            self.presentLoginAlert(
                title: "JetBrains AI 已就绪",
                message: message)
        }
    }
}
