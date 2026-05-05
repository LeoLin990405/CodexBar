import CodexBarCore
import Foundation

struct ProviderPresentation {
    let detailLine: @MainActor (ProviderPresentationContext) -> String

    @MainActor
    static func standardDetailLine(context: ProviderPresentationContext) -> String {
        let versionText = context.store.version(for: context.provider) ?? "未检测到"
        return "\(context.metadata.cliName) \(versionText)"
    }
}
