import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct ManagedCodexAccountRegistryAuditLinuxTests {
    @Test
    func `registry writes log redacted mutation metadata`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = RegistryAuditLogCapture()
        let store = FileManagedCodexAccountStore(
            fileURL: root.appendingPathComponent("managed-codex-accounts.json", isDirectory: false),
            fileManager: .default,
            auditLogger: capture.logger)

        let first = auditAccount(email: "first@example.com", providerAccountID: "account-first", home: "home-a")
        try ManagedCodexAccountRegistryAudit.withOperation(
            .addOrReauth,
            focusedAccountID: first.id,
            operationBody: {
                try store.storeAccounts(ManagedCodexAccountSet(
                    version: FileManagedCodexAccountStore.currentVersion,
                    accounts: [first]))
            })

        let added = try #require(capture.lines.last)
        #expect(added.message == "Managed Codex account registry write")
        #expect(added.metadata["event"] == "registry-write")
        #expect(added.metadata["operation"] == "add-or-reauth")
        #expect(added.metadata["rows.before"] == "none")
        #expect(added.metadata["rows.written"] == "1")
        #expect(added.metadata["added"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(first.id)) == true)
        #expect(added.metadata["removed"] == "none")
        #expect(added.metadata["sanitize.dropped"] == "none")
        #expect(added.metadata["focus"] == ManagedCodexAccountRegistryAudit.accountFingerprint(first.id))
        #expect(added.metadata["focus.present.after"] == "true")
        #expect(added.metadata["digest.after"]?.count == 16)

        let second = auditAccount(email: "second@example.com", providerAccountID: "account-second", home: "home-b")
        try ManagedCodexAccountRegistryAudit.withOperation(
            .addOrReauth,
            focusedAccountID: second.id,
            operationBody: {
                let current = try store.loadAccounts()
                try store.storeAccounts(ManagedCodexAccountSet(
                    version: current.version,
                    accounts: current.accounts + [second]))
            })

        let appended = try #require(capture.lines.last)
        #expect(appended.metadata["rows.before"] == "1")
        #expect(appended.metadata["rows.written"] == "2")
        #expect(appended.metadata["removed"] == "none")
        #expect(appended.metadata["added"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(second.id)) == true)

        try ManagedCodexAccountRegistryAudit.withOperation(
            .remove,
            focusedAccountID: first.id,
            operationBody: {
                let current = try store.loadAccounts()
                try store.storeAccounts(ManagedCodexAccountSet(
                    version: current.version,
                    accounts: current.accounts.filter { $0.id != first.id }))
            })

        let removed = try #require(capture.lines.last)
        #expect(removed.metadata["operation"] == "remove")
        #expect(removed.metadata["rows.before"] == "2")
        #expect(removed.metadata["rows.written"] == "1")
        #expect(removed.metadata["removed"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(first.id)) == true)
        #expect(removed.metadata["focus.present.after"] == "false")
        #expect(removed.metadata["focus.home.after"] == "none")

        let renderedLines = capture.lines.map { line in
            ([line.message] + Array(line.metadata.keys) + Array(line.metadata.values))
                .joined(separator: " ")
        }.joined(separator: "\n")
        #expect(renderedLines.contains("first@example.com") == false)
        #expect(renderedLines.contains("second@example.com") == false)
        #expect(renderedLines.contains("@") == false)
        #expect(renderedLines.contains("/") == false)
        #expect(renderedLines.contains("home-a") == false)
        #expect(renderedLines.contains("home-b") == false)
    }

    @Test
    func `mutation metadata never contains emails or raw home paths`() {
        let first = auditAccount(
            email: "secret-person@example.com",
            providerAccountID: "account-secret",
            home: "home-a")
        let second = auditAccount(email: "another@example.com", providerAccountID: "account-two", home: "home-b")
        let written = ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [first, second])

        let metadata = ManagedCodexAccountRegistryAudit.mutationMetadata(
            operation: .addOrReauth,
            prior: .missing,
            requested: [first, second],
            written: written,
            focusedAccountID: first.id)
        let rendered = (Array(metadata.keys) + Array(metadata.values)).joined(separator: " ")

        #expect(rendered.contains("secret-person") == false)
        #expect(rendered.contains("another") == false)
        #expect(rendered.contains("@") == false)
        #expect(rendered.contains("example.com") == false)
        #expect(rendered.contains("home-a") == false)
        #expect(rendered.contains("home-b") == false)
        #expect(rendered.contains("/") == false)
        #expect((metadata["added"]?.count ?? 0) > 0)
        #expect(metadata["digest.after"]?.count == 16)

        let duplicateSecond = auditAccount(
            email: "another@example.com",
            providerAccountID: "account-two",
            home: "home-b")
        let requested = [first, second, duplicateSecond]
        let sanitized = ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: requested)
        let droppedMetadata = ManagedCodexAccountRegistryAudit.mutationMetadata(
            operation: .registryWrite,
            prior: .missing,
            requested: requested,
            written: sanitized)
        #expect(sanitized.accounts.count == 2)
        #expect(droppedMetadata["sanitize.dropped"] != "none")
        #expect(droppedMetadata["sanitize.dropped"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(duplicateSecond.id)) == true)
        #expect(droppedMetadata["rows.requested"] == "3")
        #expect(droppedMetadata["rows.written"] == "2")

        // A duplicated id occurrence keeps its UUID in the written set but still loses one row, so
        // drop detection must compare occurrences instead of UUID presence.
        let sameIDDropped = ManagedCodexAccountRegistryAudit.mutationMetadata(
            operation: .registryWrite,
            prior: .missing,
            requested: [first, first, second],
            written: written)
        #expect(sameIDDropped["sanitize.dropped"] != "none")
        #expect(sameIDDropped["sanitize.dropped"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(first.id)) == true)
        #expect(sameIDDropped["rows.requested"] == "3")
        #expect(sameIDDropped["rows.written"] == "2")
    }

    @Test
    func `registry read metadata is redacted and stable`() throws {
        let first = auditAccount(email: "read-owner@example.com", providerAccountID: "account-read", home: "home-a")
        let accounts = ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [first])
        let metadata = ManagedCodexAccountRegistryAudit.readMetadata(accounts)
        let rendered = (Array(metadata.keys) + Array(metadata.values)).joined(separator: " ")

        #expect(metadata["event"] == "registry-read")
        #expect(metadata["rows"] == "1")
        #expect(metadata["digest"]?.count == 16)
        #expect(metadata["digest"] == ManagedCodexAccountRegistryAudit.registryDigest(accounts.accounts))
        #expect(rendered.contains("read-owner") == false)
        #expect(rendered.contains("@") == false)
        #expect(rendered.contains("/") == false)

        let capture = RegistryAuditLogCapture()
        ManagedCodexAccountRegistryAudit.logRead(accounts, logger: capture.logger)
        let line = try #require(capture.lines.last)
        #expect(line.message == "Managed Codex account registry loaded")
        #expect(line.metadata["event"] == "registry-read")
    }

    @Test
    func `home deletion logging is redacted and path normalized`() throws {
        let capture = RegistryAuditLogCapture()
        let rawPath = "/Users/fictitious/Library/Application Support/CodexBar/managed-codex-homes/private-home"
        ManagedCodexAccountRegistryAudit.logHomeDeletion(
            homePath: rawPath,
            operation: .remove,
            logger: capture.logger)
        let line = try #require(capture.lines.last)

        #expect(line.message == "Managed Codex account home deleted")
        #expect(line.metadata["event"] == "home-delete")
        #expect(line.metadata["operation"] == "remove")
        #expect(line.metadata["home"]?.count == 16)
        let rendered = ([line.message] + Array(line.metadata.values)).joined(separator: " ")
        #expect(rendered.contains("/Users") == false)
        #expect(rendered.contains("private-home") == false)
        #expect(
            ManagedCodexAccountRegistryAudit.homeFingerprint(rawPath + "/")
                == ManagedCodexAccountRegistryAudit.homeFingerprint(rawPath))
    }

    @Test
    func `store write upgrades legacy registry as migration`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("managed-codex-accounts.json", isDirectory: false)
        let account = auditAccount(email: "legacy@example.com", providerAccountID: "account-legacy", home: "home-a")
        let legacyJSON = """
        {
          "accounts": [
            {
              "createdAt": 1,
              "email": "legacy@example.com",
              "id": "\(account.id.uuidString)",
              "lastAuthenticatedAt": null,
              "managedHomePath": "\(account.managedHomePath)",
              "updatedAt": 1
            }
          ],
          "version": 2
        }
        """
        try Data(legacyJSON.utf8).write(to: fileURL)
        let capture = RegistryAuditLogCapture()
        let store = FileManagedCodexAccountStore(
            fileURL: fileURL,
            fileManager: .default,
            auditLogger: capture.logger)

        let loaded = try store.loadAccounts()
        try store.storeAccounts(loaded)

        let line = try #require(capture.lines.last)
        #expect(line.metadata["operation"] == "migration")
        #expect(line.metadata["rows.before"] == "1")
        #expect(line.metadata["rows.written"] == "1")
    }

    @Test
    func `store write warns when a duplicated id occurrence is sanitized away`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = auditAccount(
            email: "duplicate@example.com",
            providerAccountID: "account-duplicate",
            home: "home-a")
        let second = auditAccount(email: "other@example.com", providerAccountID: "account-other", home: "home-b")
        let payload = """
        {
          "accounts" : [
            {
              "createdAt" : 1,
              "email" : "duplicate@example.com",
              "id" : "\(first.id.uuidString)",
              "managedHomePath" : "\(first.managedHomePath)",
              "updatedAt" : 1
            },
            {
              "createdAt" : 1,
              "email" : "duplicate@example.com",
              "id" : "\(first.id.uuidString)",
              "managedHomePath" : "\(first.managedHomePath)",
              "updatedAt" : 1
            },
            {
              "createdAt" : 1,
              "email" : "other@example.com",
              "id" : "\(second.id.uuidString)",
              "managedHomePath" : "\(second.managedHomePath)",
              "updatedAt" : 1
            }
          ],
          "version" : 3
        }
        """
        // The decoding initializer intentionally skips sanitization, so the store receives the
        // duplicated-id occurrence exactly like a foreign or older writer could publish it.
        let decoded = try JSONDecoder().decode(ManagedCodexAccountSet.self, from: Data(payload.utf8))
        #expect(decoded.accounts.count == 3)

        let capture = RegistryAuditLogCapture()
        let store = FileManagedCodexAccountStore(
            fileURL: root.appendingPathComponent("managed-codex-accounts.json", isDirectory: false),
            fileManager: .default,
            auditLogger: capture.logger)
        try store.storeAccounts(decoded)

        let line = try #require(capture.lines.last)
        #expect(line.level == .warning)
        #expect(line.message == "Managed Codex account registry write dropped rows")
        #expect(line.metadata["sanitize.dropped"] != "none")
        #expect(line.metadata["sanitize.dropped"]?
            .contains(ManagedCodexAccountRegistryAudit.accountFingerprint(first.id)) == true)
        #expect(line.metadata["rows.requested"] == "3")
        #expect(line.metadata["rows.written"] == "2")
        #expect(try store.loadAccounts().accounts.count == 2)
    }
}

private final class RegistryAuditLogCapture: @unchecked Sendable {
    struct Line {
        let level: CodexBarLog.Level
        let message: String
        let metadata: [String: String]
    }

    private let lock = NSLock()
    private var storage: [Line] = []

    var lines: [Line] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.storage
    }

    var logger: CodexBarLogger {
        CodexBarLogger(minimumLevel: .debug) { level, message, metadata in
            self.lock.lock()
            self.storage.append(Line(
                level: level,
                message: message,
                metadata: metadata ?? [:]))
            self.lock.unlock()
        }
    }
}

private func auditAccount(
    email: String,
    providerAccountID: String,
    home: String)
    -> ManagedCodexAccount
{
    ManagedCodexAccount(
        id: UUID(),
        email: email,
        providerAccountID: providerAccountID,
        workspaceAccountID: providerAccountID,
        managedHomePath: "/Users/fictitious/Library/Application Support/CodexBar/managed-codex-homes/\(home)",
        createdAt: 1,
        updatedAt: 1,
        lastAuthenticatedAt: 1)
}
