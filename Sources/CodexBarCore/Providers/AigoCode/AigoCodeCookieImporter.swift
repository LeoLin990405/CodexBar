#if os(macOS)
import Foundation
import SweetCookieKit

/// Imports the AigoCode Supabase session from Chrome's localStorage (LevelDB).
///
/// AigoCode uses Supabase Auth which stores JWT tokens in localStorage under the key
/// `sb-myptlcacxbuuxldgouqt-auth-token`, **not** in cookies. We read Chrome's LevelDB
/// files to extract the session JSON so it can be injected into a WKWebView.
public enum AigoCodeLocalStorageImporter {
    private static let log = CodexBarLog.logger(LogCategories.aigocodeWeb)

    /// The Supabase localStorage key for AigoCode's project.
    static let supabaseTokenKey = "sb-myptlcacxbuuxldgouqt-auth-token"

    /// The origin where the token is stored.
    static let origin = "https://www.aigocode.com"

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
            if let tokenJSON = self.readSupabaseToken(from: candidate.levelDBURL) {
                log("Found Supabase session in \(candidate.label)")
                return SessionInfo(tokenJSON: tokenJSON, sourceLabel: candidate.label)
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

    // MARK: - Chrome LevelDB Discovery

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

    // MARK: - Token Extraction

    private static func readSupabaseToken(from levelDBURL: URL) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: levelDBURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        else { return nil }

        // Read newest files first (more likely to have current token)
        let files = entries.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "ldb" || ext == "log"
        }
        .sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            return (left ?? .distantPast) > (right ?? .distantPast)
        }

        for file in files {
            guard let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) else { continue }
            if let token = self.extractSupabaseToken(from: data) {
                return token
            }
        }
        return nil
    }

    private static func extractSupabaseToken(from data: Data) -> String? {
        // The LevelDB files contain binary data with embedded strings.
        // We look for the Supabase token key, then extract the JSON value that follows it.
        guard let contents = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1)
        else { return nil }

        guard contents.contains(self.supabaseTokenKey) else { return nil }

        // Find the JSON object that follows the key.
        // Pattern: the key appears, followed by a JSON object starting with {"access_t
        guard let keyRange = contents.range(of: self.supabaseTokenKey) else { return nil }

        // Search for the JSON start after the key
        let afterKey = contents[keyRange.upperBound...]
        guard let jsonStart = afterKey.range(of: "{\"access_t") ??
              afterKey.range(of: "{\"expires") ??
              afterKey.range(of: "{\"provider_") else { return nil }

        // Extract the JSON by finding matching braces
        let jsonSubstring = afterKey[jsonStart.lowerBound...]
        if let json = self.extractJSONObject(from: String(jsonSubstring)) {
            return json
        }

        return nil
    }

    /// Extract a balanced JSON object from the start of a string.
    private static func extractJSONObject(from string: String) -> String? {
        guard string.hasPrefix("{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex = string.startIndex

        for (i, char) in string.enumerated() {
            let idx = string.index(string.startIndex, offsetBy: i)
            if escaped {
                escaped = false
                continue
            }
            if char == "\\" && inString {
                escaped = true
                continue
            }
            if char == "\"" {
                inString = !inString
                continue
            }
            if inString { continue }
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = string.index(after: idx)
                    let result = String(string[string.startIndex..<endIndex])
                    // Validate it's actually JSON
                    if let data = result.data(using: .utf8),
                       (try? JSONSerialization.jsonObject(with: data)) != nil
                    {
                        return result
                    }
                    return nil
                }
            }
            // Bail if we're reading too much (malformed data)
            if i > 50000 { return nil }
        }
        return nil
    }
}
#endif
