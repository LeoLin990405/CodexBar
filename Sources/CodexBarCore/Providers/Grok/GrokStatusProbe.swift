import Foundation

enum GrokProductUsageDetails {
    static func sections(for products: [GrokProductUsage]) -> [ProviderDetailSection] {
        let rows = products.enumerated()
            .filter { $0.element.usedPercent.isFinite && $0.element.usedPercent > 0 }
            .sorted {
                $0.element.usedPercent == $1.element.usedPercent
                    ? $0.offset < $1.offset
                    : $0.element.usedPercent > $1.element.usedPercent
            }
            .map { _, usage in
                let product = usage.product.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = switch product {
                case "GrokBuild": "Grok Build"
                case "GrokChat": "Grok Chat"
                case "GrokImagine": "Grok Imagine"
                case "GrokAppBuilder": "Grok App Builder"
                default: product
                }
                return ProviderDetailSection.makeRow(
                    id: "grok.product.\(product)",
                    label: label,
                    value: UsageFormatter.percentString(usage.usedPercent))
            }
        guard !rows.isEmpty else { return [] }
        return [.makeSection(title: "Usage breakdown", rows: rows)]
    }
}

public struct GrokUsageSnapshot: Sendable {
    public let billing: GrokBillingResponse?
    public let webBilling: GrokWebBillingSnapshot?
    public let credentials: GrokCredentials?
    public let localSummary: GrokLocalSessionSummary?
    public let cliVersion: String?
    public let diagnostic: String?
    public let updatedAt: Date
    public let subscriptionTier: String?

    public init(
        billing: GrokBillingResponse?,
        webBilling: GrokWebBillingSnapshot? = nil,
        credentials: GrokCredentials?,
        localSummary: GrokLocalSessionSummary?,
        cliVersion: String?,
        updatedAt: Date,
        diagnostic: String? = nil,
        subscriptionTier: String? = nil)
    {
        self.billing = billing
        self.webBilling = webBilling
        self.credentials = credentials
        self.localSummary = localSummary
        self.cliVersion = cliVersion
        self.diagnostic = diagnostic
        self.updatedAt = updatedAt
        self.subscriptionTier = subscriptionTier
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        // Primary window: credit usage (against included limit) from the CLI RPC,
        // falling back to the web billing RPC used by grok.com when the agent surface lacks billing.
        var primary: RateWindow?
        var details: [ProviderDetailSection] = []
        if let billing,
           let percent = billing.monthlyUsedPercent
        {
            primary = RateWindow(
                usedPercent: percent,
                windowMinutes: billing.billingPeriodMinutes,
                resetsAt: billing.billingPeriodEndDate,
                resetDescription: nil)
        } else if let webBilling,
                  let percent = webBilling.usedPercent
        {
            // Do not infer the full quota cadence from the remaining time until reset; a
            // monthly window near its reset would otherwise be misclassified as weekly.
            primary = RateWindow(
                usedPercent: percent,
                windowMinutes: webBilling.windowMinutes,
                resetsAt: webBilling.resetsAt,
                resetDescription: nil)
            details = GrokProductUsageDetails.sections(for: webBilling.productUsage)
        }

        let identity = ProviderIdentitySnapshot(
            providerID: .grok,
            accountEmail: self.credentials?.email,
            accountOrganization: self.credentials?.teamId,
            loginMethod: GrokPlan.loginMethod(
                subscriptionTier: self.subscriptionTier ?? self.webBilling?.subscriptionTier,
                credentials: self.credentials))

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: self.webBilling?.prepaidBalanceUSD.map { balance in
                ProviderCostSnapshot(
                    used: 0,
                    limit: 0,
                    currencyCode: "USD",
                    balance: balance,
                    balanceUpdatedAt: self.updatedAt,
                    updatedAt: self.updatedAt)
            },
            costUsage: self.localSummary?.toCostUsageTokenSnapshot(
                historyDays: GrokLocalSessionScanner.defaultLookbackDays),
            details: details,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}

public struct GrokStatusProbe: Sendable {
    public static let teamUsageUnavailableMessage =
        "Grok team usage is unavailable from the current billing surface; identity is still available."
    public static let usageUnavailableMessage =
        "Grok usage is unavailable because its billing sources did not report a usage percentage."

    var localSummary: @Sendable ([String: String]) async throws -> GrokLocalSessionSummary? = {
        try await GrokLocalSessionScanner.summarizeOffMainThread(env: $0)
    }

    var settingsTransport: any ProviderHTTPTransport = ProviderHTTPClient.shared
    var identityOnlyFallback: @Sendable (GrokCredentials?, Bool, Error?) -> Bool =
        GrokStatusProbe.shouldUseIdentityOnlyFallback
    /// Best-effort grok.com usage lookup for ACP credits that carry an active period and a wallet
    /// balance but omit the usage percentage (a zero-usage week). Injectable so probe tests stay
    /// hermetic instead of reaching the network.
    var enrichUnknownCredits: @Sendable (GrokWebBillingSnapshot, GrokCredentials?) async throws
        -> GrokWebBillingSnapshot = { snapshot, credentials in
            try await GrokStatusProbe.enrichingUnknownCredits(snapshot, credentials: credentials)
        }

    public init() {}

    public static func detectVersion(env: [String: String] = ProcessInfo.processInfo.environment)
        -> String?
    {
        guard let binary = BinaryLocator.resolveGrokBinary(env: env) else { return nil }
        guard
            let output = ProviderVersionDetector.run(
                path: binary,
                args: ["--version"],
                environment: env,
                mergeStandardError: true)
        else { return nil }
        // Output is like "grok 0.1.210 (8b63e9068c)" — strip the leading "grok " so
        // callers can prefix the CLI name themselves without duplicating it.
        let withoutPrefix = output.replacingOccurrences(
            of: #"^grok\s+"#,
            with: "",
            options: [.regularExpression])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return withoutPrefix.isEmpty ? nil : withoutPrefix
    }

    public func fetch(env: [String: String] = ProcessInfo.processInfo.environment) async throws
        -> GrokUsageSnapshot
    {
        // Credentials are optional: we still show identity-less state if the user
        // hasn't logged in, with a clear hint via the RPC error.
        let credentials = try? GrokCredentialsStore.load(env: env)

        var billing: GrokBillingResponse?
        var webBilling: GrokWebBillingSnapshot?
        var rpcError: Error?
        var billingAttempted = false
        do {
            let client = try GrokRPCClient(environment: env)
            defer { client.shutdown() }
            try await client.initialize()
            billingAttempted = true
            switch try await client.fetchBilling() {
            case let .legacy(response): billing = response
            case let .credits(response): webBilling = response
            }
        } catch {
            rpcError = error
        }

        // ACP reports an active period and prepaid balance while omitting `creditUsagePercent`
        // early in a billing period. Ask the grok.com bearer surface for a validated percentage
        // before the wallet-only answer ends the pipeline; keep the ACP answer when it has none.
        if let credits = webBilling, credits.usedPercent == nil {
            webBilling = try await self.enrichingCredits(credits, credentials: credentials)
        }

        let hasBilling = billing != nil || webBilling != nil
        let isIdentityOnly = !hasBilling && self.identityOnlyFallback(credentials, billingAttempted, rpcError)
        // Terminal CLI failures must reach the provider's web fallback without scanning discarded history.
        guard hasBilling || isIdentityOnly else {
            throw rpcError ?? GrokRPCError.notAuthenticated
        }

        let localSummary = try await self.localSummary(env)
        let cliVersion = Self.detectVersion(env: env)
        // Preserve the original eligibility checkpoint after potentially slow local work.
        if isIdentityOnly, !self.identityOnlyFallback(credentials, billingAttempted, rpcError) {
            throw rpcError ?? GrokRPCError.notAuthenticated
        }
        let subscriptionTier = try await Self.loadSettingsTier(
            credentials: credentials,
            session: self.settingsTransport)
        return GrokUsageSnapshot(
            billing: billing,
            webBilling: webBilling,
            credentials: isIdentityOnly ? credentials : Self.credentialsForSnapshot(
                credentials: credentials,
                billing: billing,
                webBilling: webBilling),
            localSummary: localSummary,
            cliVersion: cliVersion,
            updatedAt: Date(),
            diagnostic: isIdentityOnly ? Self.teamUsageUnavailableMessage : nil,
            subscriptionTier: subscriptionTier)
    }

    /// Enrichment is best-effort: cancellation propagates, but any other failure keeps the
    /// already-valid wallet-only billing instead of discarding it.
    func enrichingCredits(
        _ snapshot: GrokWebBillingSnapshot,
        credentials: GrokCredentials?) async throws -> GrokWebBillingSnapshot
    {
        do {
            return try await self.enrichUnknownCredits(snapshot, credentials)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            return snapshot
        }
    }

    static func identityOnlySnapshot(
        credentials: GrokCredentials,
        localSummary: GrokLocalSessionSummary?,
        cliVersion: String?,
        updatedAt: Date = .init(),
        subscriptionTier: String? = nil) -> GrokUsageSnapshot
    {
        GrokUsageSnapshot(
            billing: nil,
            webBilling: nil,
            credentials: credentials,
            localSummary: localSummary,
            cliVersion: cliVersion,
            updatedAt: updatedAt,
            diagnostic: GrokStatusProbe.teamUsageUnavailableMessage,
            subscriptionTier: subscriptionTier)
    }

    /// The ACP credits answer can describe an active billing period and a prepaid balance while
    /// omitting `creditUsagePercent` (a zero-usage week). That is unknown usage, and an unknown
    /// percent yields no rate window, so ask the grok.com bearer surface with the same auth-file
    /// token (no browser cookies) before accepting the wallet-only answer. This reuses the CLI-proxy
    /// retry's bounded budget and strict validation: only a wire-published percentage or a
    /// parser-validated implicit zero from an active period can replace unknown usage, and the
    /// ACP period, plan, and wallet metadata stay authoritative.
    static func enrichingUnknownCredits(
        _ snapshot: GrokWebBillingSnapshot,
        credentials: GrokCredentials?,
        budget: Duration = GrokOAuthFetchStrategy.unknownUsageEnrichmentBudget,
        grpcBilling: @escaping GrokWebFetchStrategy.ProxyBillingFetch = {
            try await GrokWebBillingFetcher.fetch(credentials: $0)
        }) async throws -> GrokWebBillingSnapshot
    {
        guard snapshot.usedPercent == nil,
              let credentials,
              !credentials.isExpired
        else {
            return snapshot
        }
        return try await GrokOAuthFetchStrategy.resolvingUnknownUsage(
            snapshot,
            credentials: credentials,
            budget: budget,
            grpcBilling: grpcBilling)
            .snapshot
    }

    static let settingsJoinGrace = Duration.seconds(2)

    static func loadSettingsTier(
        credentials: GrokCredentials?,
        session transport: any ProviderHTTPTransport = ProviderHTTPClient.shared) async throws -> String?
    {
        guard let credentials, !credentials.isExpired else { return nil }
        let sourceTask = Task<String?, Error> {
            try await GrokCLISettingsFetcher.subscriptionTierDisplay(
                credentials: credentials,
                session: transport)
        }
        let outcome = await BoundedTaskJoin(sourceTask: sourceTask).value(joinGrace: Self.settingsJoinGrace)
        try Task.checkCancellation()
        switch outcome {
        case let .value(tier):
            return tier
        case .timedOut:
            return nil
        case let .failure(error):
            if error is CancellationError {
                throw CancellationError()
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                throw urlError
            }
            return nil
        }
    }

    static func isBillingMethodUnavailable(_ error: Error?) -> Bool {
        guard let error,
              case let GrokRPCError.requestFailed(_, code) = error
        else {
            return false
        }
        return code == -32601
    }

    static func shouldUseIdentityOnlyFallback(
        credentials: GrokCredentials?,
        billingAttempted: Bool,
        error: Error?) -> Bool
    {
        guard billingAttempted,
              let credentials,
              !credentials.isExpired,
              credentials.isTeamPrincipal
        else {
            return false
        }
        return Self.isBillingMethodUnavailable(error)
    }

    static func credentialsForSnapshot(
        credentials: GrokCredentials?,
        billing: GrokBillingResponse?,
        webBilling: GrokWebBillingSnapshot? = nil) -> GrokCredentials?
    {
        // If remote usage succeeded, xAI accepted auth and the local
        // identity is still useful even when the persisted expires_at is stale.
        if billing != nil || webBilling != nil {
            return credentials
        }
        return credentials.flatMap { $0.isExpired ? nil : $0 }
    }

    static func shouldSurfaceRemoteAuthError(_ error: Error?) -> Bool {
        guard let error = error as? GrokWebBillingError else { return false }
        switch error {
        case let .requestFailed(status, _):
            return status == 401 || status == 403
        case let .rpcFailed(status, _):
            return status == 16
        case .missingCredentials, .emptyResponse, .invalidResponse, .teamUsageUnsupported, .parseFailed:
            return false
        }
    }
}
