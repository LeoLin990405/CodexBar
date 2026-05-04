import Foundation
import Testing
@testable import CodexBarCore

struct ProviderFetchBackgroundPolicyTests {
    @Test
    func `pipeline skips user initiated strategy during background refresh`() async throws {
        let pipeline = ProviderFetchPipeline(resolveStrategies: { _ in
            [
                TestFetchStrategy(
                    id: "web",
                    kind: .webDashboard,
                    backgroundPolicy: .userInitiatedOnly,
                    sourceLabel: "web"),
                TestFetchStrategy(
                    id: "api",
                    kind: .apiToken,
                    backgroundPolicy: .allowed,
                    sourceLabel: "api"),
            ]
        })

        let outcome = await ProviderInteractionContext.$current.withValue(.background) {
            await pipeline.fetch(context: Self.makeContext(), provider: .codex)
        }

        let result = try outcome.result.get()
        #expect(result.sourceLabel == "api")
        #expect(outcome.attempts.map(\.strategyID) == ["web", "api"])
        #expect(outcome.attempts[0].wasAvailable == false)
        #expect(outcome.attempts[0].errorDescription?.contains("background") == true)
    }

    @Test
    func `pipeline allows user initiated strategy during user refresh`() async throws {
        let pipeline = ProviderFetchPipeline(resolveStrategies: { _ in
            [
                TestFetchStrategy(
                    id: "web",
                    kind: .webDashboard,
                    backgroundPolicy: .userInitiatedOnly,
                    sourceLabel: "web"),
                TestFetchStrategy(
                    id: "api",
                    kind: .apiToken,
                    backgroundPolicy: .allowed,
                    sourceLabel: "api"),
            ]
        })

        let outcome = await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await pipeline.fetch(context: Self.makeContext(), provider: .codex)
        }

        let result = try outcome.result.get()
        #expect(result.sourceLabel == "web")
        #expect(outcome.attempts.map(\.strategyID) == ["web"])
    }

    @Test
    func `doubao and stepfun split web dashboard from api strategy`() async {
        let doubaoStrategies = await ProviderDescriptorRegistry
            .descriptor(for: .doubao)
            .fetchPlan
            .pipeline
            .resolveStrategies(Self.makeContext(sourceMode: .auto))

        #expect(doubaoStrategies.map(\.id) == ["doubao.console", "doubao.api"])
        #expect(doubaoStrategies[0].kind == .webDashboard)
        #expect(doubaoStrategies[0].backgroundPolicy == .userInitiatedOnly)
        #expect(doubaoStrategies[0].requiresBrowserSession)
        #expect(doubaoStrategies[0].requiresKeychainAccess)
        #expect(doubaoStrategies[1].kind == .apiToken)
        #expect(doubaoStrategies[1].requiresBrowserSession == false)
        #expect(doubaoStrategies[1].requiresKeychainAccess == false)

        let stepFunStrategies = await ProviderDescriptorRegistry
            .descriptor(for: .stepfun)
            .fetchPlan
            .pipeline
            .resolveStrategies(Self.makeContext(sourceMode: .auto))

        #expect(stepFunStrategies.map(\.id) == ["stepfun.webDashboard", "stepfun.api"])
        #expect(stepFunStrategies[0].kind == .webDashboard)
        #expect(stepFunStrategies[0].backgroundPolicy == .userInitiatedOnly)
        #expect(stepFunStrategies[0].requiresBrowserSession)
        #expect(stepFunStrategies[0].requiresKeychainAccess)
        #expect(stepFunStrategies[1].kind == .apiToken)
        #expect(stepFunStrategies[1].requiresBrowserSession == false)
        #expect(stepFunStrategies[1].requiresKeychainAccess == false)

        let kimiStrategies = await ProviderDescriptorRegistry
            .descriptor(for: .kimi)
            .fetchPlan
            .pipeline
            .resolveStrategies(Self.makeContext(sourceMode: .auto))

        #expect(kimiStrategies.map(\.id) == ["kimi.token", "kimi.web"])
        #expect(kimiStrategies[0].kind == .apiToken)
        #expect(kimiStrategies[0].requiresBrowserSession == false)
        #expect(kimiStrategies[1].kind == .web)
        #expect(kimiStrategies[1].backgroundPolicy == .userInitiatedOnly)
        #expect(kimiStrategies[1].requiresKeychainAccess)

        let perplexityStrategies = await ProviderDescriptorRegistry
            .descriptor(for: .perplexity)
            .fetchPlan
            .pipeline
            .resolveStrategies(Self.makeContext(sourceMode: .auto))

        #expect(perplexityStrategies.map(\.id) == ["perplexity.session", "perplexity.web"])
        #expect(perplexityStrategies[0].kind == .apiToken)
        #expect(perplexityStrategies[0].requiresBrowserSession == false)
        #expect(perplexityStrategies[1].kind == .web)
        #expect(perplexityStrategies[1].backgroundPolicy == .userInitiatedOnly)
        #expect(perplexityStrategies[1].requiresKeychainAccess)

        let traeStrategies = await ProviderDescriptorRegistry
            .descriptor(for: .trae)
            .fetchPlan
            .pipeline
            .resolveStrategies(Self.makeContext(sourceMode: .auto))

        #expect(traeStrategies.map(\.id) == ["trae.web", "trae.local"])
        #expect(traeStrategies[0].kind == .web)
        #expect(traeStrategies[0].backgroundPolicy == .userInitiatedOnly)
        #expect(traeStrategies[1].kind == .localProbe)
        #expect(traeStrategies[1].requiresBrowserSession == false)
    }

    @Test
    func `web strategies default to conservative background interval`() {
        let web = TestFetchStrategy(
            id: "web",
            kind: .webDashboard,
            backgroundPolicy: .allowed,
            sourceLabel: "web")
        let api = TestFetchStrategy(
            id: "api",
            kind: .apiToken,
            backgroundPolicy: .allowed,
            sourceLabel: "api")

        #expect(web.minimumBackgroundRefreshInterval == TimeInterval(5 * 60))
        #expect(api.minimumBackgroundRefreshInterval == nil)
    }

    @Test
    func `background auto uses api strategy when safe fallback token exists`() async {
        let aigoContext = Self.makeContext(
            env: ["AIGOCODE_API_KEY": "aigo-key"])
        let aigoStrategies = await ProviderInteractionContext.$current.withValue(.background) {
            await ProviderDescriptorRegistry
                .descriptor(for: .aigocode)
                .fetchPlan
                .pipeline
                .resolveStrategies(aigoContext)
        }
        #expect(aigoStrategies.map(\.id) == ["aigocode.api"])

        let alibabaContext = Self.makeContext(
            env: ["ALIBABA_CODING_PLAN_API_KEY": "alibaba-key"])
        let alibabaStrategies = await ProviderInteractionContext.$current.withValue(.background) {
            await ProviderDescriptorRegistry
                .descriptor(for: .alibaba)
                .fetchPlan
                .pipeline
                .resolveStrategies(alibabaContext)
        }
        #expect(alibabaStrategies.map(\.id) == ["alibaba-coding-plan.api"])

        let miniMaxContext = Self.makeContext(
            env: ["MINIMAX_API_KEY": "sk-cp-test"])
        let miniMaxStrategies = await ProviderInteractionContext.$current.withValue(.background) {
            await ProviderDescriptorRegistry
                .descriptor(for: .minimax)
                .fetchPlan
                .pipeline
                .resolveStrategies(miniMaxContext)
        }
        #expect(miniMaxStrategies.map(\.id) == ["minimax.api"])

        let kimiContext = Self.makeContext(env: ["KIMI_AUTH_TOKEN": "kimi-token"])
        let kimiStrategies = await ProviderInteractionContext.$current.withValue(.background) {
            await ProviderDescriptorRegistry
                .descriptor(for: .kimi)
                .fetchPlan
                .pipeline
                .resolveStrategies(kimiContext)
        }
        #expect(kimiStrategies.map(\.id) == ["kimi.token", "kimi.web"])
        #expect(kimiStrategies[0].minimumBackgroundRefreshInterval == nil)
        #expect(kimiStrategies[1].backgroundPolicy == .userInitiatedOnly)

        let perplexityContext = Self.makeContext(env: ["PERPLEXITY_SESSION_TOKEN": "pplx-token"])
        let perplexityStrategies = await ProviderInteractionContext.$current.withValue(.background) {
            await ProviderDescriptorRegistry
                .descriptor(for: .perplexity)
                .fetchPlan
                .pipeline
                .resolveStrategies(perplexityContext)
        }
        #expect(perplexityStrategies.map(\.id) == ["perplexity.session", "perplexity.web"])
        #expect(perplexityStrategies[0].minimumBackgroundRefreshInterval == nil)
        #expect(perplexityStrategies[1].backgroundPolicy == .userInitiatedOnly)
    }

    @Test
    func `user initiated auto keeps web first for providers with api fallback`() async {
        let context = Self.makeContext(env: ["AIGOCODE_API_KEY": "aigo-key"])
        let strategies = await ProviderInteractionContext.$current.withValue(.userInitiated) {
            await ProviderDescriptorRegistry
                .descriptor(for: .aigocode)
                .fetchPlan
                .pipeline
                .resolveStrategies(context)
        }

        #expect(strategies.map(\.id) == ["aigocode.webDashboard", "aigocode.api"])
    }

    private static func makeContext(
        sourceMode: ProviderSourceMode = .auto,
        env: [String: String] = [:]) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return ProviderFetchContext(
            runtime: .app,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: env,
            settings: nil,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
    }
}

private struct TestFetchStrategy: ProviderFetchStrategy {
    let id: String
    let kind: ProviderFetchKind
    let backgroundPolicy: ProviderFetchBackgroundPolicy
    let sourceLabel: String

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        self.makeResult(
            usage: UsageSnapshot(
                primary: nil,
                secondary: nil,
                updatedAt: Date()),
            sourceLabel: self.sourceLabel)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
