import Foundation

/// Tracks API request consumption locally by recording rate-limit snapshots over time.
/// Computes weekly (7-day) and monthly (30-day) accumulated usage from deltas between samples.
/// Used by providers (Doubao, Qwen) that only expose rate-limit headers without dedicated usage APIs.
public actor LocalUsageTracker {
    public static let shared = LocalUsageTracker()

    private static let sampleInterval: TimeInterval = 60
    private static let retentionDays: TimeInterval = 31 * 24 * 60 * 60
    private static let weekSeconds: TimeInterval = 7 * 24 * 60 * 60
    private static let monthSeconds: TimeInterval = 30 * 24 * 60 * 60

    private var records: [String: [Sample]] = [:]
    private var loaded = false

    private struct Sample: Codable, Sendable {
        let timestamp: Date
        let remaining: Int
        let limit: Int
    }

    public struct AccumulatedUsage: Sendable {
        public let weeklyRequests: Int
        public let monthlyRequests: Int
        public let weeklyLimit: Int
        public let monthlyLimit: Int
    }

    private init() {}

    /// Record a rate-limit sample and return accumulated weekly/monthly usage.
    public func record(
        provider: UsageProvider,
        remaining: Int,
        limit: Int,
        now: Date = Date()) -> AccumulatedUsage
    {
        self.ensureLoaded()
        let key = provider.rawValue

        var samples = self.records[key] ?? []

        // Throttle: skip if last sample is too recent and values unchanged
        if let last = samples.last {
            let elapsed = now.timeIntervalSince(last.timestamp)
            if elapsed < Self.sampleInterval, last.remaining == remaining, last.limit == limit {
                return self.computeUsage(samples: samples, limit: limit, now: now)
            }
        }

        samples.append(Sample(timestamp: now, remaining: remaining, limit: limit))

        // Prune old samples
        let cutoff = now.addingTimeInterval(-Self.retentionDays)
        samples.removeAll { $0.timestamp < cutoff }

        self.records[key] = samples
        self.persist()

        return self.computeUsage(samples: samples, limit: limit, now: now)
    }

    /// Get accumulated usage without recording a new sample.
    public func usage(for provider: UsageProvider) -> AccumulatedUsage? {
        self.ensureLoaded()
        guard let samples = self.records[provider.rawValue], !samples.isEmpty else { return nil }
        let limit = samples.last?.limit ?? 0
        return self.computeUsage(samples: samples, limit: limit, now: Date())
    }

    // MARK: - Computation

    private func computeUsage(samples: [Sample], limit: Int, now: Date) -> AccumulatedUsage {
        let weekCutoff = now.addingTimeInterval(-Self.weekSeconds)
        let monthCutoff = now.addingTimeInterval(-Self.monthSeconds)

        let weeklyRequests = Self.sumConsumption(
            samples: samples.filter { $0.timestamp >= weekCutoff })
        let monthlyRequests = Self.sumConsumption(
            samples: samples.filter { $0.timestamp >= monthCutoff })

        // Estimate limits: daily limit * 7 or * 30
        // We use the current window limit as a proxy for daily capacity
        let weeklyLimit = limit > 0 ? limit * 7 : 0
        let monthlyLimit = limit > 0 ? limit * 30 : 0

        return AccumulatedUsage(
            weeklyRequests: weeklyRequests,
            monthlyRequests: monthlyRequests,
            weeklyLimit: weeklyLimit,
            monthlyLimit: monthlyLimit)
    }

    /// Sum consumption from consecutive samples by tracking remaining-count drops.
    /// When remaining increases (reset occurred), we don't count that as negative consumption.
    private static func sumConsumption(samples: [Sample]) -> Int {
        guard samples.count >= 2 else { return 0 }

        var total = 0
        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]

            if curr.limit == prev.limit, curr.remaining < prev.remaining {
                // Same window, remaining dropped → consumption
                total += prev.remaining - curr.remaining
            }
            // If remaining increased or limit changed → reset happened, skip
        }
        return total
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !self.loaded else { return }
        self.loaded = true
        self.records = Self.readFromDisk()
    }

    private static func fileURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return root
            .appendingPathComponent("CodexBar", isDirectory: true)
            .appendingPathComponent("local-usage-tracker.json", isDirectory: false)
    }

    private static func readFromDisk() -> [String: [Sample]] {
        guard let data = try? Data(contentsOf: fileURL()),
              let decoded = try? JSONDecoder.iso8601Decoder.decode([String: [Sample]].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        guard let data = try? encoder.encode(self.records) else { return }
        let url = Self.fileURL()
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Best-effort; ignore write failures.
        }
    }
}

extension JSONDecoder {
    fileprivate static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
