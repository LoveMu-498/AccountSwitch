import Foundation
import Testing
@testable import AccountSwitch

@MainActor
struct AccountAuthorizationTests {
    @Test(arguments: [false, true])
    func turningOffVerificationRequiresSuccessfulAuthentication(approved: Bool) async throws {
        let name = "AccountSwitchTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        var prompts = 0
        let auth = AccountAuthorization(preferences: preferences) { _ in
            prompts += 1
            #expect(preferences.object(forKey: AccountPreferences.verifyActions) == nil)
            return approved
        }
        try await auth.setVerificationRequired(false)
        #expect(prompts == 1)
        #expect(preferences.object(forKey: AccountPreferences.verifyActions) as? Bool == (approved ? false : nil))
    }

    @Test func turningVerificationBackOnDoesNotRequireAuthentication() async throws {
        let name = "AccountSwitchTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(false, forKey: AccountPreferences.verifyActions)
        let auth = AccountAuthorization(preferences: preferences) { _ in
            Issue.record("Enabling the protection should not prompt")
            return false
        }
        try await auth.setVerificationRequired(true)
        #expect(preferences.bool(forKey: AccountPreferences.verifyActions))
    }

    @Test func cancelledAuthenticationCannotTurnOffVerification() async throws {
        let name = "AccountSwitchTests.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let auth = AccountAuthorization(preferences: preferences) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return true
        }
        let change = Task { try await auth.setVerificationRequired(false) }
        await #expect(throws: CancellationError.self) { try await change.value }
        #expect(preferences.object(forKey: AccountPreferences.verifyActions) == nil)
        #expect(!auth.isAuthenticating)
    }
}
