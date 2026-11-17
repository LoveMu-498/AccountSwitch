import Foundation
import LocalAuthentication
import Observation

enum AccountPreferences {
    static let verifyActions = "verifyAccountActions"
    static let showMenuBar = "showAccountSwitchInMenuBar"
}

@MainActor
@Observable
final class AccountAuthorization {
    private(set) var isAuthenticating = false
    private let preferences: UserDefaults
    private let evaluate: @MainActor (String) async throws -> Bool

    init(preferences: UserDefaults = .standard,
         evaluate: @escaping @MainActor (String) async throws -> Bool = AccountAuthorization.evaluateOwner) {
        self.preferences = preferences
        self.evaluate = evaluate
    }

    func verify(_ reason: String) async throws -> Bool {
        guard !isAuthenticating else { return false }
        guard verificationRequired else { return true }
        return try await verifyOwner(reason)
    }

    func setVerificationRequired(_ required: Bool) async throws {
        guard !isAuthenticating, required != verificationRequired else { return }
        if !required {
            guard try await verifyOwner("关闭切换和移除账号时的身份验证。") else { return }
        }
        preferences.set(required, forKey: AccountPreferences.verifyActions)
    }

    private var verificationRequired: Bool {
        preferences.object(forKey: AccountPreferences.verifyActions) as? Bool ?? true
    }

    private func verifyOwner(_ reason: String) async throws -> Bool {
        try Task.checkCancellation()
        isAuthenticating = true
        defer { isAuthenticating = false }
        let verified = try await evaluate(reason)
        try Task.checkCancellation()
        return verified
    }

    private static func evaluateOwner(_ reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw Failure.unavailable
        }

        let invalidate: @MainActor @Sendable () -> Void = { context.invalidate() }
        defer { invalidate() }
        do {
            return try await withTaskCancellationHandler {
                try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            } onCancel: {
                Task { @MainActor in invalidate() }
            }
        } catch let error as LAError where [.userCancel, .systemCancel, .appCancel].contains(error.code) {
            return false
        } catch let error as LAError where error.code == .authenticationFailed {
            throw Failure.rejected
        }
    }

    private enum Failure: LocalizedError {
        case unavailable
        case rejected

        var errorDescription: String? {
            switch self {
            case .unavailable: "此 Mac 暂时无法验证身份，请检查 Touch ID 或登录密码。"
            case .rejected: "身份验证未通过，请重试。"
            }
        }
    }
}
