import CodexBarCore
import Testing
@testable import CodexBar

struct MenuBarDisplayTextTests {
    @Test
    func `pace mode falls back to percent when reset metadata is unavailable`() {
        let window = RateWindow(
            usedPercent: 97,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: nil)

        let text = MenuBarDisplayText.displayText(
            mode: .pace,
            percentWindow: window,
            pace: nil,
            showUsed: true)

        #expect(text == "97%")
    }
}
