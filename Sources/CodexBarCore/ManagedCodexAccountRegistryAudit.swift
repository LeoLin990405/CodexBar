import Crypto
import Foundation

/// Redacted diagnostics for the managed Codex account registry.
///
/// The managed-account store used to persist and delete saved accounts without emitting a log line, so a
/// report such as steipete/CodexBar#4499 ("a saved account disappeared after 3-4 days") could not be
/// attributed to a writer. These helpers emit one structured line per registry mutation, one line when a
/// managed home is removed, and a single launch digest line per process.
///
/// Redaction contract: no email, raw managed-home path, token, or credential content is logged. Account ids
/// and home paths are reduced to short SHA-256 prefixes, and only counts, digests, operation names, and
/// existence flags are written.
package enum ManagedCodexAccountRegistryAudit {
    package enum Operation: String, Sendable {
        case addOrReauth = "add-or-reauth"
        case remove
        case promotionAppend = "promotion-append"
        case promotionRepair = "promotion-repair"
        case promotionRefresh = "promotion-refresh"
        case migration
        case registryWrite = "registry-write"
    }

    package struct Context: Sendable {
        package let operation: Operation
        package let focusedAccountID: UUID?

        package init(operation: Operation, focusedAccountID: UUID?) {
            self.operation = operation
            self.focusedAccountID = focusedAccountID
        }
    }

    package enum PriorRegistry: Sendable {
        case missing
        case unreadable
        case loaded(ManagedCodexAccountSet)
    }

    @TaskLocal package static var operationContext: Context?

    package static var currentOperation: Context? {
        self.operationContext
    }

    package static func withOperation<T>(
        _ operation: Operation,
        focusedAccountID: UUID? = nil,
        operationBody: () throws -> T)
        rethrows -> T
    {
        try self.$operationContext.withValue(
            Context(operation: operation, focusedAccountID: focusedAccountID),
            operation: operationBody)
    }

    // MARK: - Redaction primitives

    package static func accountFingerprint(_ id: UUID) -> String {
        self.sha256Prefix(id.uuidString.lowercased())
    }

    package static func homeFingerprint(_ path: String) -> String {
        let standardizedPath = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        return self.sha256Prefix(standardizedPath)
    }

    /// Stable digest of the registry contents (counts and identity/home fingerprints only).
    package static func registryDigest(_ accounts: [ManagedCodexAccount]) -> String {
        let rows = accounts
            .map { "\(self.accountFingerprint($0.id)):\(self.homeFingerprint($0.managedHomePath))" }
            .sorted()
            .joined(separator: "\n")
        return self.sha256Prefix(rows)
    }

    // MARK: - Metadata builders

    package static func mutationMetadata(
        operation: Operation,
        prior: PriorRegistry,
        requested: [ManagedCodexAccount],
        written: ManagedCodexAccountSet,
        focusedAccountID: UUID? = nil)
        -> [String: String]
    {
        let priorAccounts: [ManagedCodexAccount] = switch prior {
        case .missing, .unreadable: []
        case let .loaded(accounts): accounts.accounts
        }
        let priorIDs = Set(priorAccounts.map(\.id))
        let writtenIDs = Set(written.accounts.map(\.id))
        let added = written.accounts.filter { priorIDs.contains($0.id) == false }
        let removed = priorAccounts.filter { writtenIDs.contains($0.id) == false }
        let sanitizeDropped = requested.filter { writtenIDs.contains($0.id) == false }

        var metadata: [String: String] = [
            "event": "registry-write",
            "operation": operation.rawValue,
            "rows.before": self.rowCount(prior),
            "rows.requested": "\(requested.count)",
            "rows.written": "\(written.accounts.count)",
            "digest.before": self.priorDigest(prior),
            "digest.after": self.registryDigest(written.accounts),
            "added": self.render(added),
            "removed": self.render(removed),
            "sanitize.dropped": self.render(sanitizeDropped),
        ]
        if let focusedAccountID {
            let priorHome = priorAccounts.first { $0.id == focusedAccountID }
            let writtenHome = written.account(id: focusedAccountID)
            metadata["focus"] = self.accountFingerprint(focusedAccountID)
            metadata["focus.present.after"] = writtenHome != nil ? "true" : "false"
            metadata["focus.home.before"] = priorHome.map { self.homeFingerprint($0.managedHomePath) } ?? "none"
            metadata["focus.home.after"] = writtenHome.map { self.homeFingerprint($0.managedHomePath) } ?? "none"
        }
        return metadata
    }

    package static func readMetadata(_ accounts: ManagedCodexAccountSet) -> [String: String] {
        [
            "event": "registry-read",
            "version": "\(accounts.version)",
            "rows": "\(accounts.accounts.count)",
            "digest": self.registryDigest(accounts.accounts),
        ]
    }

    // MARK: - Logging

    package static func logMutation(
        operation: Operation,
        prior: PriorRegistry,
        requested: [ManagedCodexAccount],
        written: ManagedCodexAccountSet,
        focusedAccountID: UUID? = nil,
        logger: CodexBarLogger? = nil)
    {
        let logger = logger ?? CodexBarLog.logger(LogCategories.codexAccounts)
        let metadata = self.mutationMetadata(
            operation: operation,
            prior: prior,
            requested: requested,
            written: written,
            focusedAccountID: focusedAccountID)
        // A write that silently drops rows is a data-loss signal, not a routine state change.
        if metadata["sanitize.dropped"] == "none" {
            logger.info("Managed Codex account registry write", metadata: metadata)
        } else {
            logger.warning("Managed Codex account registry write dropped rows", metadata: metadata)
        }
    }

    package static func logWriteFailure(
        operation: Operation,
        requestedCount: Int,
        logger: CodexBarLogger? = nil)
    {
        let logger = logger ?? CodexBarLog.logger(LogCategories.codexAccounts)
        logger.error("Managed Codex account registry write failed", metadata: [
            "event": "registry-write-failed",
            "operation": operation.rawValue,
            "rows.requested": "\(requestedCount)",
        ])
    }

    /// Logs the registry row count and a redacted digest once per process so a reporter can diff launches.
    package static func logLaunchRead(_ accounts: ManagedCodexAccountSet, logger: CodexBarLogger? = nil) {
        self.launchReadLock.lock()
        let shouldLog = self.didLogLaunchRead == false
        self.didLogLaunchRead = true
        self.launchReadLock.unlock()
        guard shouldLog else { return }
        self.logRead(accounts, logger: logger)
    }

    package static func logRead(_ accounts: ManagedCodexAccountSet, logger: CodexBarLogger? = nil) {
        let logger = logger ?? CodexBarLog.logger(LogCategories.codexAccounts)
        logger.info("Managed Codex account registry loaded", metadata: self.readMetadata(accounts))
    }

    package static func logReadFailure(logger: CodexBarLogger? = nil) {
        let logger = logger ?? CodexBarLog.logger(LogCategories.codexAccounts)
        logger.warning("Managed Codex account registry unreadable", metadata: [
            "event": "registry-read-failed",
            "rows": "unknown",
        ])
    }

    package static func logHomeDeletion(
        homePath: String,
        operation: Operation,
        logger: CodexBarLogger? = nil)
    {
        let logger = logger ?? CodexBarLog.logger(LogCategories.codexAccounts)
        logger.info("Managed Codex account home deleted", metadata: [
            "event": "home-delete",
            "operation": operation.rawValue,
            "home": self.homeFingerprint(homePath),
        ])
    }

    // MARK: - Private

    // Mutations are rare; the diagnostic line is intentionally emitted once per process at launch.
    private static let launchReadLock = NSLock()
    private nonisolated(unsafe) static var didLogLaunchRead = false

    private static func rowCount(_ prior: PriorRegistry) -> String {
        switch prior {
        case .missing: "none"
        case .unreadable: "unreadable"
        case let .loaded(accounts): "\(accounts.accounts.count)"
        }
    }

    private static func priorDigest(_ prior: PriorRegistry) -> String {
        switch prior {
        case .missing: "none"
        case .unreadable: "unreadable"
        case let .loaded(accounts): self.registryDigest(accounts.accounts)
        }
    }

    private static func render(_ accounts: [ManagedCodexAccount]) -> String {
        guard accounts.isEmpty == false else { return "none" }
        let shown = accounts.prefix(8).map {
            "\(self.accountFingerprint($0.id)):\(self.homeFingerprint($0.managedHomePath))"
        }
        let remaining = accounts.count - shown.count
        let suffix = remaining > 0 ? ",+\(remaining)" : ""
        return shown.joined(separator: ",") + suffix
    }

    private static func sha256Prefix(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
