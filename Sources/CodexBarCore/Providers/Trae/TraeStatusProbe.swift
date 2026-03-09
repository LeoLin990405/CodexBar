import Foundation

public struct TraeStatusSnapshot: Sendable {
    public let isRunning: Bool
    public let version: String?
    public let updatedAt: Date

    public init(isRunning: Bool, version: String?, updatedAt: Date) {
        self.isRunning = isRunning
        self.version = version
        self.updatedAt = updatedAt
    }

    public func toUsageSnapshot() -> UsageSnapshot {
        let usedPercent: Double = self.isRunning ? 0 : 100
        let resetDescription: String = self.isRunning
            ? "Active — free tier"
            : "Not running"

        let primary = RateWindow(
            usedPercent: usedPercent,
            windowMinutes: nil,
            resetsAt: nil,
            resetDescription: resetDescription)

        let identity = ProviderIdentitySnapshot(
            providerID: .trae,
            accountEmail: nil,
            accountOrganization: nil,
            loginMethod: nil)

        return UsageSnapshot(
            primary: primary,
            secondary: nil,
            tertiary: nil,
            providerCost: nil,
            updatedAt: self.updatedAt,
            identity: identity)
    }
}

public enum TraeStatusProbeError: LocalizedError, Sendable {
    case notInstalled
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Trae is not installed."
        case .notRunning:
            "Trae is not running."
        }
    }
}

public struct TraeStatusProbe: Sendable {
    private static let log = CodexBarLog.logger(LogCategories.traeUsage)

    public static func probe() async throws -> TraeStatusSnapshot {
        let appPath = "/Applications/Trae.app"
        let fm = FileManager.default
        guard fm.fileExists(atPath: appPath) else {
            throw TraeStatusProbeError.notInstalled
        }

        let isRunning = Self.isTraeRunning()
        let version = Self.traeVersion(appPath: appPath)

        Self.log.debug("Trae probe: running=\(isRunning) version=\(version ?? "unknown")")

        return TraeStatusSnapshot(
            isRunning: isRunning,
            version: version,
            updatedAt: Date())
    }

    private static func isTraeRunning() -> Bool {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "Trae.app"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func traeVersion(appPath: String) -> String? {
        let plistPath = "\(appPath)/Contents/Info.plist"
        guard let plistData = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleShortVersionString"] as? String
    }
}
