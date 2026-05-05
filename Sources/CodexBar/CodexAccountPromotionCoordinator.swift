import Foundation
import Observation

struct CodexSystemAccountPromotionUserFacingError: Error, Equatable {
    let title: String
    let message: String
}

@MainActor
@Observable
final class CodexAccountPromotionCoordinator {
    let service: CodexAccountPromotionService
    weak var managedAccountCoordinator: ManagedCodexAccountCoordinator?
    private(set) var isAuthenticatingLiveAccount = false
    private(set) var isPromotingSystemAccount = false
    private(set) var userFacingError: CodexSystemAccountPromotionUserFacingError?

    init(
        service: CodexAccountPromotionService,
        managedAccountCoordinator: ManagedCodexAccountCoordinator? = nil)
    {
        self.service = service
        self.managedAccountCoordinator = managedAccountCoordinator
    }

    convenience init(
        settingsStore: SettingsStore,
        usageStore: UsageStore,
        managedAccountCoordinator: ManagedCodexAccountCoordinator? = nil)
    {
        self.init(
            service: CodexAccountPromotionService(settingsStore: settingsStore, usageStore: usageStore),
            managedAccountCoordinator: managedAccountCoordinator)
    }

    func promote(managedAccountID: UUID)
        async -> Result<CodexAccountPromotionResult, CodexSystemAccountPromotionUserFacingError>
    {
        self.userFacingError = nil

        guard !self.isInteractionBlocked() else {
            let error = Self.interactionBlockedError()
            self.userFacingError = error
            return .failure(error)
        }

        self.isPromotingSystemAccount = true
        defer { self.isPromotingSystemAccount = false }

        do {
            let result = try await self.service.promoteManagedAccount(id: managedAccountID)
            return .success(result)
        } catch {
            let mapped = Self.mapUserFacingError(error)
            self.userFacingError = mapped
            return .failure(mapped)
        }
    }

    func clearError() {
        self.userFacingError = nil
    }

    func setLiveReauthenticationInProgress(_ isInProgress: Bool) {
        self.isAuthenticatingLiveAccount = isInProgress
    }

    func isInteractionBlocked() -> Bool {
        self.isPromotingSystemAccount ||
            self.isAuthenticatingLiveAccount ||
            self.managedAccountCoordinator?.hasConflictingManagedAccountOperationInFlight == true
    }

    private static func interactionBlockedError() -> CodexSystemAccountPromotionUserFacingError {
        CodexSystemAccountPromotionUserFacingError(
            title: "无法切换系统账号",
            message: "请先完成当前托管账号变更，再切换系统账号。")
    }

    static func mapUserFacingError(_ error: Error) -> CodexSystemAccountPromotionUserFacingError {
        let title = "无法切换系统账号"

        if let error = error as? CodexAccountPromotionError {
            let message = switch error {
            case .targetManagedAccountNotFound:
                "该账号已不在 CodexBar 中。请刷新账号列表后重试。"
            case .targetManagedAccountAuthMissing:
                "CodexBar 找不到该账号保存的认证信息。请重新认证后重试。"
            case .targetManagedAccountAuthUnreadable:
                "CodexBar 无法读取该账号保存的认证信息。请重新认证后重试。"
            case .liveAccountUnreadable:
                "CodexBar 无法读取这台 Mac 上的当前系统账号。"
            case .liveAccountMissingIdentityForPreservation:
                "切换前，CodexBar 无法安全保留当前系统账号。"
            case .liveAccountAPIKeyOnlyUnsupported:
                "CodexBar 无法替换仅使用 API key 登录的系统账号。"
            case .displacedLiveManagedAccountConflict:
                "CodexBar 发现另一个托管账号已使用当前系统账号。" +
                    "请先处理重复账号，再切换。"
            case .displacedLiveImportFailed:
                "切换前，CodexBar 无法保存当前系统账号。"
            case .managedStoreCommitFailed:
                "CodexBar 无法更新托管账号存储。"
            case .liveAuthSwapFailed:
                "CodexBar 无法替换这台 Mac 上正在使用的 Codex 认证。"
            }

            return CodexSystemAccountPromotionUserFacingError(title: title, message: message)
        }

        return CodexSystemAccountPromotionUserFacingError(title: title, message: error.localizedDescription)
    }
}
