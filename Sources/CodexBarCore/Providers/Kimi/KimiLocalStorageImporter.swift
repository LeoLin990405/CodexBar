#if os(macOS)
import Foundation
import SweetCookieKit

/// Imports Kimi auth tokens from Chrome's localStorage.
///
/// Kimi stores `access_token` and `refresh_token` as JWTs in localStorage
/// on `https://www.kimi.com`, not in cookies.
public enum KimiLocalStorageImporter {
    private static let log = CodexBarLog.logger(LogCategories.kimiCookie)

    private static let origins = [
        "https://www.kimi.com",
        "https://kimi.com",
    ]

    /// The localStorage key that holds the JWT access token.
    private static let accessTokenKey = "access_token"
    private static let refreshTokenKey = "refresh_token"

    public struct SessionInfo: Sendable {
        public let accessToken: String
        public let refreshToken: String?
        public let sourceLabel: String
    }

    public static func importSession(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) -> SessionInfo?
    {
        let log: (String) -> Void = { msg in
            logger?("[kimi-storage] \(msg)")
            self.log.debug(msg)
        }

        let candidates = self.chromeLocalStorageCandidates(browserDetection: browserDetection)
        log("Found \(candidates.count) Chrome profile candidate(s)")

        for candidate in candidates {
            if let session = self.readKimiSession(from: candidate.levelDBURL, label: candidate.label, logger: log) {
                return session
            }
        }

        log("No Kimi access_token found in any browser profile")
        return nil
    }

    public static func hasSession(
        browserDetection: BrowserDetection = BrowserDetection()) -> Bool
    {
        self.importSession(browserDetection: browserDetection) != nil
    }

    // MARK: - LevelDB Reading

    private static func readKimiSession(
        from levelDBURL: URL,
        label: String,
        logger: ((String) -> Void)?) -> SessionInfo?
    {
        for origin in self.origins {
            let entries = ChromiumLocalStorageReader.readEntries(
                for: origin,
                in: levelDBURL,
                logger: logger)

            var accessToken: String?
            var refreshToken: String?

            for entry in entries {
                let value = entry.value.trimmingCharacters(in: .controlCharacters)
                guard !value.isEmpty else { continue }

                if entry.key == self.accessTokenKey, value.hasPrefix("eyJ") {
                    accessToken = value
                } else if entry.key == self.refreshTokenKey, value.hasPrefix("eyJ") {
                    refreshToken = value
                }
            }

            if let accessToken {
                logger?("Found Kimi access_token in \(label) (origin: \(origin))")
                return SessionInfo(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    sourceLabel: label)
            }
        }

        // Fallback: text scan
        let textEntries = ChromiumLocalStorageReader.readTextEntries(
            in: levelDBURL,
            logger: logger)

        var accessToken: String?
        var refreshToken: String?

        for entry in textEntries {
            let value = entry.value.trimmingCharacters(in: .controlCharacters)
            guard !value.isEmpty, value.hasPrefix("eyJ") else { continue }

            if entry.key.hasSuffix(self.accessTokenKey) {
                accessToken = value
            } else if entry.key.hasSuffix(self.refreshTokenKey) {
                refreshToken = value
            }
        }

        if let accessToken {
            logger?("Found Kimi access_token in \(label) (text scan)")
            return SessionInfo(
                accessToken: accessToken,
                refreshToken: refreshToken,
                sourceLabel: label)
        }

        return nil
    }

    // MARK: - Chrome Profile Discovery

    private struct LocalStorageCandidate {
        let label: String
        let levelDBURL: URL
    }

    private static func chromeLocalStorageCandidates(
        browserDetection: BrowserDetection) -> [LocalStorageCandidate]
    {
        let browsers: [Browser] = [
            .chrome,
            .chromeBeta,
            .chromeCanary,
            .arc,
            .arcBeta,
            .arcCanary,
            .chromium,
        ]

        let installedBrowsers = browsers.browsersWithProfileData(using: browserDetection)
        let roots = ChromiumProfileLocator
            .roots(for: installedBrowsers, homeDirectories: BrowserCookieClient.defaultHomeDirectories())
            .map { (url: $0.url, labelPrefix: $0.labelPrefix) }

        var candidates: [LocalStorageCandidate] = []
        for root in roots {
            candidates.append(contentsOf: self.profileCandidates(root: root.url, labelPrefix: root.labelPrefix))
        }
        return candidates
    }

    private static func profileCandidates(root: URL, labelPrefix: String) -> [LocalStorageCandidate] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        let profileDirs = entries.filter { url in
            guard let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory), isDir else {
                return false
            }
            let name = url.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ") || name.hasPrefix("user-")
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return profileDirs.compactMap { dir in
            let levelDBURL = dir.appendingPathComponent("Local Storage").appendingPathComponent("leveldb")
            guard FileManager.default.fileExists(atPath: levelDBURL.path) else { return nil }
            let label = "\(labelPrefix) \(dir.lastPathComponent)"
            return LocalStorageCandidate(label: label, levelDBURL: levelDBURL)
        }
    }
}
#endif
