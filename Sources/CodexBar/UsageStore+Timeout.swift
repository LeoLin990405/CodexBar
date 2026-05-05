import Foundation

extension UsageStore {
    nonisolated static func runWithTimeout(
        seconds: Double,
        operation: @escaping @Sendable () async -> String) async -> String
    {
        await withTaskGroup(of: String?.self) { group -> String in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next()?.flatMap(\.self)
            group.cancelAll()
            return result ?? "探测在 \(Int(seconds)) 秒后超时"
        }
    }
}
