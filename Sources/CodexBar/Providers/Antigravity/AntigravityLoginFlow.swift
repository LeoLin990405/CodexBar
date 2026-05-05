import CodexBarCore

@MainActor
extension StatusItemController {
    func runAntigravityLoginFlow() async {
        self.loginPhase = .idle
        self.presentLoginAlert(
            title: "Antigravity 登录由应用内管理",
            message: "请打开 Antigravity 登录，然后刷新 CodexBar。")
    }
}
