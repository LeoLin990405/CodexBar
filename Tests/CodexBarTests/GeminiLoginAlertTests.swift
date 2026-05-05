import Testing
@testable import CodexBar

struct GeminiLoginAlertTests {
    @Test
    func `returns alert for missing binary`() {
        let result = GeminiLoginRunner.Result(outcome: .missingBinary)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "未找到 Gemini CLI")
        #expect(info?.message == "请安装 Gemini CLI（npm i -g @google/gemini-cli）后重试。")
    }

    @Test
    func `returns alert for launch failure`() {
        let result = GeminiLoginRunner.Result(outcome: .launchFailed("Boom"))
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info?.title == "无法为 Gemini 打开终端")
        #expect(info?.message == "Boom")
    }

    @Test
    func `returns nil on success`() {
        let result = GeminiLoginRunner.Result(outcome: .success)
        let info = StatusItemController.geminiLoginAlertInfo(for: result)
        #expect(info == nil)
    }
}
