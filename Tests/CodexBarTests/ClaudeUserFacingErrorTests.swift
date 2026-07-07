import Testing
@testable import CodexBarCore

struct ClaudeUserFacingErrorTests {
    @Test
    func `claude web unauthorized error suggests refreshing login`() {
        let error = ClaudeWebAPIFetcher.FetchError.unauthorized

        #expect(error.errorDescription == "Sign in to claude.ai or refresh Claude cookies, then retry.")
    }
}
