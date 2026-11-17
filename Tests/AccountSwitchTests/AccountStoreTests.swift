import Foundation
import Testing
@testable import AccountSwitch

@MainActor
struct AccountStoreTests {
    @Test func keychainFailureKeepsAccountRestorable() async throws {
        try await withArchive { file in
            let (store, entry) = try removedAccount(at: file)
            await #expect(throws: FixtureError.keychain) {
                try await store.permanentlyRemove(entry) { profile in
                    #expect(profile.id == entry.id)
                    #expect(AccountStore(file: file).removedAccounts.first?.deletionPending == true)
                    throw FixtureError.keychain
                }
            }
            let reopened = AccountStore(file: file)
            let retained = try #require(reopened.removedAccounts.first)
            #expect(retained.deletionPending != true)
            try reopened.restore(retained)
            #expect(reopened.profiles.map(\.id) == [entry.id])
        }
    }

    @Test func archiveFailureBeforeDeletionLeavesKeychainUntouched() async throws {
        try await withArchive { file in
            let (store, entry) = try removedAccount(at: file)
            let saved = file.appendingPathExtension("backup")
            try FileManager.default.moveItem(at: file, to: saved)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            await #expect(throws: AccountStore.DeletionError.cannotStart) {
                try await store.permanentlyRemove(entry) { _ in
                    Issue.record("The password operation ran before the deletion was recorded")
                }
            }
            #expect(store.removedAccounts.first?.deletionPending != true)
        }
    }

    @Test func unfinishedDeletionSurvivesRestartAndCanBeRetried() async throws {
        try await withArchive { file in
            let (store, entry) = try removedAccount(at: file)
            let saved = file.appendingPathExtension("backup")
            await #expect(throws: AccountStore.DeletionError.cannotFinish) {
                try await store.permanentlyRemove(entry) { _ in
                    try FileManager.default.moveItem(at: file, to: saved)
                    try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
                }
            }
            try FileManager.default.removeItem(at: file)
            try FileManager.default.moveItem(at: saved, to: file)
            let reopened = AccountStore(file: file)
            let pending = try #require(reopened.removedAccounts.first)
            #expect(pending.deletionPending == true)
            try reopened.restore(pending)
            #expect(reopened.profiles.isEmpty)
            try await reopened.permanentlyRemove(pending) { _ in }
            #expect(AccountStore(file: file).removedAccounts.isEmpty)
        }
    }

    @Test func negativeLegacyIndexRestoresAtStart() async throws {
        try await withArchive { file in
            let (_, entry) = try removedAccount(at: file)
            var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var removed = try #require(json["removed"] as? [[String: Any]])
            removed[0]["index"] = -4
            json["removed"] = removed
            try JSONSerialization.data(withJSONObject: json).write(to: file)
            let reopened = AccountStore(file: file)
            try reopened.save(profile(named: "Other"))
            try reopened.restore(try #require(reopened.removedAccounts.first))
            #expect(reopened.profiles.first?.id == entry.id)
            #expect(reopened.removedAccounts.isEmpty)
        }
    }

    @Test func passwordEditorCannotWriteAfterAccountWasRemoved() async throws {
        try await withArchive { file in
            let (store, entry) = try removedAccount(at: file)
            await #expect(throws: AccountStore.ValidationError.changedAccount) {
                try await store.editPassword(for: entry.profile) {
                    Issue.record("A stale password editor could recreate a credential")
                }
            }
        }
    }

    private enum FixtureError: Error { case keychain }

    private func withArchive(_ operation: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AccountSwitchTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await operation(directory.appending(path: "accounts.json"))
    }

    private func removedAccount(at file: URL) throws -> (AccountStore, AccountStore.RemovedAccount) {
        let store = AccountStore(file: file)
        let profile = profile(named: "Test")
        try store.save(profile)
        try store.remove(profile)
        return try (store, #require(store.removedAccounts.first))
    }

    private func profile(named name: String) -> AccountProfile {
        var profile = AccountProfile()
        profile.name = name
        profile.login = "\(name.lowercased())@example.invalid"
        return profile
    }
}
