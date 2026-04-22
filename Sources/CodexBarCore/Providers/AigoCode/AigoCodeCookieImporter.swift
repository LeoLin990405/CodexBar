#if os(macOS)
import Foundation
import SweetCookieKit

/// Imports the AigoCode Supabase session from Chrome's localStorage.
///
/// AigoCode uses Supabase Auth which stores JWT tokens in localStorage under the key
/// `sb-myptlcacxbuuxldgouqt-auth-token`, **not** in cookies. We use SweetCookieKit's
/// `ChromiumLocalStorageReader` to properly parse Chrome's LevelDB files.
public enum AigoCodeLocalStorageImporter {
    private static let log = CodexBarLog.logger(LogCategories.aigocodeWeb)

    /// The Supabase localStorage key for AigoCode's project.
    static let supabaseTokenKey = "sb-myptlcacxbuuxldgouqt-auth-token"

    /// The origins where the token may be stored.
    private static let origins = [
        "https://www.aigocode.com",
        "https://aigocode.com",
    ]

    /// Extracted Supabase session from browser localStorage.
    public struct SessionInfo: Sendable {
        /// The raw JSON string stored under the Supabase token key.
        public let tokenJSON: String
        /// Which browser/profile the token was found in.
        public let sourceLabel: String
    }

    /// Attempts to extract the Supabase session from Chrome's localStorage.
    public static func importSession(
        browserDetection: BrowserDetection = BrowserDetection(),
        logger: ((String) -> Void)? = nil) -> SessionInfo?
    {
        let log: (String) -> Void = { msg in
            logger?("[aigocode-storage] \(msg)")
            self.log.debug(msg)
        }

        let candidates = self.chromeLocalStorageCandidates(browserDetection: browserDetection)
        log("Found \(candidates.count) Chrome profile candidate(s)")

        for candidate in candidates {
            if let session = self.readSupabaseSession(from: candidate.levelDBURL, label: candidate.label, logger: log) {
                return session
            }
        }

        log("No Supabase session found in any browser profile")
        return nil
    }

    /// Quick check for session availability.
    public static func hasSession(
        browserDetection: BrowserDetection = BrowserDetection()) -> Bool
    {
        self.importSession(browserDetection: browserDetection) != nil
    }

    // MARK: - LevelDB Reading

    private static func readSupabaseSession(
        from levelDBURL: URL,
        label: String,
        logger: ((String) -> Void)?) -> SessionInfo?
    {
        // Use SweetCookieKit's proper LevelDB parser for origin-scoped entries
        for origin in self.origins {
            let entries = ChromiumLocalStorageReader.readEntries(
                for: origin,
                in: levelDBURL,
                logger: logger)

            for entry in entries where entry.key == self.supabaseTokenKey {
                let value = entry.value.trimmingCharacters(in: .controlCharacters)
                guard !value.isEmpty else { continue }
                // Validate it's actually JSON with access_token
                if let data = value.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["access_token"] != nil
                {
                    logger?("Found valid Supabase session in \(label) (origin: \(origin))")
                    return SessionInfo(tokenJSON: value, sourceLabel: label)
                }
            }
        }

        // Fallback: scan text entries for the key (handles edge cases)
        let textEntries = ChromiumLocalStorageReader.readTextEntries(
            in: levelDBURL,
            logger: logger)

        for entry in textEntries where entry.key.contains(self.supabaseTokenKey) {
            let value = entry.value.trimmingCharacters(in: .controlCharacters)
            guard !value.isEmpty else { continue }
            if let data = value.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["access_token"] != nil
            {
                logger?("Found valid Supabase session in \(label) (text scan)")
                return SessionInfo(tokenJSON: value, sourceLabel: label)
            }
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
