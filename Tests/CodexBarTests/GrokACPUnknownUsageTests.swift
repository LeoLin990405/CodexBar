import Foundation
import Testing
@testable import CodexBarCore

/// Regression coverage for #4674: the ACP `_x.ai/billing` answer can describe an active weekly
/// period and a prepaid balance while omitting `creditUsagePercent` (a zero-usage week). That
/// wallet-only answer is valid and must keep its prepaid balance, but it must also regain the
/// weekly Credits window through the bounded, validated grok.com usage enrichment rather than
/// ending the pipeline with unknown usage.
struct GrokACPUnknownUsageTests {
    @Test
    func `active ACP period with omitted percentage adopts validated implicit zero`() async throws {
        let fixture = try Self.makeFixture(credentials: .valid, prepaidCents: 123)
        defer { fixture.cleanup() }
        let probe = Self.makeProbe { snapshot, credentials in
            #expect(credentials?.accessToken == "synthetic-token")
            return try await GrokStatusProbe.enrichingUnknownCredits(
                snapshot,
                credentials: credentials,
                grpcBilling: { _ in
                    // grok.com reports its own reset; the ACP period stays authoritative.
                    GrokWebBillingSnapshot(
                        usedPercent: 0,
                        resetsAt: fixture.periodEnd.addingTimeInterval(-90),
                        windowMinutes: 10080,
                        usedPercentIsWirePublished: false,
                        usedPercentIsImplicitZero: true)
                })
        }

        let snapshot = try await probe.fetch(env: fixture.environment)
        #expect(snapshot.billing == nil)
        #expect(snapshot.webBilling?.usedPercent == 0)
        #expect(snapshot.webBilling?.usedPercentIsImplicitZero == true)
        #expect(snapshot.webBilling?.windowMinutes == 10080)
        #expect(snapshot.webBilling?.resetsAt == fixture.periodEnd)
        #expect(snapshot.webBilling?.prepaidBalanceUSD == 1.23)
        #expect(snapshot.diagnostic == nil)

        let usage = snapshot.toUsageSnapshot()
        let primary = try #require(usage.primary)
        #expect(primary.usedPercent == 0)
        #expect(primary.windowMinutes == 10080)
        #expect(primary.resetsAt == fixture.periodEnd)
        #expect(usage.providerCost?.balance == 1.23)
    }

    @Test
    func `published ACP percentage never triggers the grok.com retry`() async throws {
        let fixture = try Self.makeFixture(credentials: .valid, publishedPercent: 5)
        defer { fixture.cleanup() }
        let probe = Self.makeProbe { _, _ in
            Issue.record("Enrichment must not run when ACP already published a percentage")
            throw GrokWebBillingError.parseFailed
        }

        let usage = try await probe.fetch(env: fixture.environment).toUsageSnapshot()
        #expect(usage.primary?.usedPercent == 5)
    }

    @Test
    func `enrichment without a validated percentage keeps unknown usage and the wallet`() async throws {
        let fixture = try Self.makeFixture(credentials: .valid, prepaidCents: 123)
        defer { fixture.cleanup() }
        let probe = Self.makeProbe { snapshot, credentials in
            try await GrokStatusProbe.enrichingUnknownCredits(
                snapshot,
                credentials: credentials,
                grpcBilling: { _ in GrokWebBillingSnapshot(usedPercent: nil, resetsAt: nil) })
        }

        let snapshot = try await probe.fetch(env: fixture.environment)
        let usage = snapshot.toUsageSnapshot()
        #expect(snapshot.webBilling?.usedPercent == nil)
        #expect(usage.primary == nil)
        #expect(usage.providerCost?.balance == 1.23)
    }

    @Test
    func `enrichment failure cannot discard already-valid wallet-only billing`() async throws {
        let fixture = try Self.makeFixture(credentials: .valid, prepaidCents: 123)
        defer { fixture.cleanup() }
        let probe = Self.makeProbe { _, _ in
            throw GrokWebBillingError.requestFailed(503, "synthetic outage")
        }

        let snapshot = try await probe.fetch(env: fixture.environment)
        let usage = snapshot.toUsageSnapshot()
        #expect(snapshot.webBilling?.prepaidBalanceUSD == 1.23)
        #expect(usage.primary == nil)
        #expect(usage.providerCost?.balance == 1.23)
    }

    @Test(arguments: [CredentialsMode.expired, .missing])
    func `expired or missing credentials skip enrichment but keep the wallet`(_ mode: CredentialsMode) async throws {
        let fixture = try Self.makeFixture(credentials: mode, prepaidCents: 123)
        defer { fixture.cleanup() }
        // The default seam must short-circuit before any grok.com request: this test would hang or
        // fail hermeticity if it reached the network.
        let probe = GrokStatusProbe()

        let snapshot = try await probe.fetch(env: fixture.environment)
        let usage = snapshot.toUsageSnapshot()
        #expect(usage.primary == nil)
        #expect(usage.providerCost?.balance == 1.23)
    }

    @Test
    func `enrichment cancellation propagates instead of settling for unknown usage`() async throws {
        let fixture = try Self.makeFixture(credentials: .valid, prepaidCents: 123)
        defer { fixture.cleanup() }
        let probe = Self.makeProbe { _, _ in
            throw CancellationError()
        }

        do {
            _ = try await probe.fetch(env: fixture.environment)
            Issue.record("Expected ACP usage enrichment cancellation to propagate")
        } catch is CancellationError {
            // Expected: the caller canceled instead of waiting for wallet-only data.
        }
    }

    @Test
    func `published percentage and live credentials never enter the bounded retry`() async throws {
        let snapshot = GrokWebBillingSnapshot(
            usedPercent: 5,
            resetsAt: Date(timeIntervalSince1970: 1_900_000_000),
            windowMinutes: 10080,
            subscriptionTier: "SuperGrok Heavy",
            prepaidBalanceUSD: 1.23)
        let enriched = try await GrokStatusProbe.enrichingUnknownCredits(
            snapshot,
            credentials: Self.validCredentials,
            grpcBilling: { _ in
                Issue.record("Published ACP usage must not schedule another request")
                throw GrokWebBillingError.parseFailed
            })
        #expect(enriched == snapshot)
    }

    @Test
    func `missing or expired credentials never enter the bounded retry`() async throws {
        let snapshot = Self.unknownCreditsSnapshot()
        let credentialSets: [GrokCredentials?] = [nil, Self.expiredCredentials]
        for credentials in credentialSets {
            let enriched = try await GrokStatusProbe.enrichingUnknownCredits(
                snapshot,
                credentials: credentials,
                grpcBilling: { _ in
                    Issue.record("grok.com billing must not run without non-expired ACP credentials")
                    throw GrokWebBillingError.missingCredentials
                })
            #expect(enriched == snapshot)
        }
    }

    @Test
    func `unvalidated zero cannot replace unknown ACP usage`() async throws {
        let snapshot = Self.unknownCreditsSnapshot()
        let enriched = try await GrokStatusProbe.enrichingUnknownCredits(
            snapshot,
            credentials: Self.validCredentials,
            grpcBilling: { _ in
                GrokWebBillingSnapshot(
                    usedPercent: 0,
                    resetsAt: nil,
                    usedPercentIsWirePublished: false,
                    usedPercentIsImplicitZero: false)
            })
        #expect(enriched == snapshot)
        #expect(enriched.usedPercent == nil)
    }

    @Test
    func `bounded retry timeout keeps the ACP period, plan, and wallet`() async throws {
        let snapshot = Self.unknownCreditsSnapshot()
        let enriched = try await GrokStatusProbe.enrichingUnknownCredits(
            snapshot,
            credentials: Self.validCredentials,
            budget: .milliseconds(20),
            grpcBilling: { _ in
                try await Task.sleep(for: .seconds(30))
                return GrokWebBillingSnapshot(usedPercent: 99, resetsAt: nil)
            })
        #expect(enriched == snapshot)
    }

    @Test
    func `published grok.com percentage adopts the ACP period, plan, and wallet`() async throws {
        let snapshot = Self.unknownCreditsSnapshot()
        let enriched = try await GrokStatusProbe.enrichingUnknownCredits(
            snapshot,
            credentials: Self.validCredentials,
            grpcBilling: { _ in
                GrokWebBillingSnapshot(
                    usedPercent: 12,
                    resetsAt: Date(timeIntervalSince1970: 1_950_000_000),
                    windowMinutes: 10080,
                    usedPercentIsWirePublished: true)
            })
        #expect(enriched.usedPercent == 12)
        #expect(enriched.usedPercentIsWirePublished)
        #expect(enriched.resetsAt == snapshot.resetsAt)
        #expect(enriched.windowMinutes == snapshot.windowMinutes)
        #expect(enriched.subscriptionTier == snapshot.subscriptionTier)
        #expect(enriched.prepaidBalanceUSD == snapshot.prepaidBalanceUSD)
    }

    // MARK: - Synthetic ACP fixture

    /// The `@Test(arguments:)` entry point is internal, so its parameter type must not be private.
    enum CredentialsMode: Sendable {
        case valid, expired, missing
    }

    private struct ACPFixture: Sendable {
        let root: URL
        let environment: [String: String]
        let periodEnd: Date

        func cleanup() {
            try? FileManager.default.removeItem(at: self.root)
        }
    }

    private static func makeFixture(
        credentials: CredentialsMode,
        prepaidCents: Int? = nil,
        publishedPercent: Double? = nil) throws -> ACPFixture
    {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-acp-unknown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()
        let periodStart = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) - 3 * 86400)
        let periodEnd = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down) + 4 * 86400)
        let startString = formatter.string(from: periodStart)
        let endString = formatter.string(from: periodEnd)

        if credentials != .missing {
            let expiresAt = credentials == .expired ? "2000-01-01T00:00:00Z" : "2099-01-01T00:00:00Z"
            let auth: [String: Any] = [
                "https://auth.x.ai::fake-client": [
                    "key": "synthetic-token",
                    "refresh_token": "synthetic-refresh",
                    "email": "grok@example.com",
                    "auth_mode": "oidc",
                    "principal_type": "User",
                    "expires_at": expiresAt,
                ],
            ]
            try JSONSerialization.data(withJSONObject: auth)
                .write(to: root.appendingPathComponent("auth.json"))
        }

        var config: [String: Any] = [
            "currentPeriod": [
                "type": "USAGE_PERIOD_TYPE_WEEKLY",
                "start": startString,
                "end": endString,
            ],
        ]
        if let prepaidCents {
            config["prepaidBalance"] = ["val": prepaidCents]
        }
        if let publishedPercent {
            config["creditUsagePercent"] = publishedPercent
        }
        let billing: [String: Any] = ["config": config, "subscription_tier": "SuperGrok Heavy"]
        let requestLog = root.appendingPathComponent("billing-requests.jsonl")

        func reply(id: Int, result: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(
                withJSONObject: ["jsonrpc": "2.0", "id": id, "result": result])
            return try #require(String(bytes: data, encoding: .utf8))
        }
        let initialize = try reply(id: 1, result: [:])
        let billingReply = try reply(id: 2, result: billing)
        let binary = root.appendingPathComponent("grok-fixture")
        let script = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
            printf '%s\\n' 'grok synthetic-version'
            exit 0
        fi
        IFS= read -r initialize_request
        printf '%s\\n' '\(initialize)'
        IFS= read -r billing_request || exit 0
        printf '%s\\n' "$billing_request" >> "\(requestLog.path)"
        printf '%s\\n' '\(billingReply)'
        """
        try script.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        return try ACPFixture(
            root: root,
            environment: [
                "HOME": root.path,
                "GROK_HOME": root.path,
                "GROK_CLI_PATH": binary.path,
                "PATH": "/usr/bin:/bin",
            ],
            periodEnd: #require(ISO8601DateParser.parse(endString)))
    }

    private static func makeProbe(
        enrich: @escaping @Sendable (GrokWebBillingSnapshot, GrokCredentials?) async throws
            -> GrokWebBillingSnapshot) -> GrokStatusProbe
    {
        var probe = GrokStatusProbe()
        probe.localSummary = { _ in nil }
        probe.settingsTransport = ProviderHTTPTransportHandler { request in
            let response = try #require(HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (Data("{}".utf8), response)
        }
        probe.enrichUnknownCredits = enrich
        return probe
    }

    private static func unknownCreditsSnapshot() -> GrokWebBillingSnapshot {
        GrokWebBillingSnapshot(
            usedPercent: nil,
            resetsAt: Date(timeIntervalSince1970: 1_900_000_000),
            windowMinutes: 10080,
            subscriptionTier: "SuperGrok Heavy",
            prepaidBalanceUSD: 1.23)
    }

    private static let validCredentials = GrokCredentials(
        accessToken: "synthetic-token",
        refreshToken: nil,
        scope: "https://auth.x.ai::test",
        authMode: "oidc",
        userId: nil,
        email: nil,
        firstName: nil,
        lastName: nil,
        teamId: nil,
        oidcIssuer: nil,
        oidcClientId: nil,
        expiresAt: .distantFuture,
        createTime: nil)

    private static let expiredCredentials = GrokCredentials(
        accessToken: "synthetic-token",
        refreshToken: nil,
        scope: "https://auth.x.ai::test",
        authMode: "oidc",
        userId: nil,
        email: nil,
        firstName: nil,
        lastName: nil,
        teamId: nil,
        oidcIssuer: nil,
        oidcClientId: nil,
        expiresAt: Date(timeIntervalSince1970: 1_000_000),
        createTime: nil)
}
