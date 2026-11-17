import Foundation
import Observation

@MainActor
@Observable
final class AccountStore {
    enum ValidationError: LocalizedError {
        case missingFields
        case removedAccount
        case changedAccount
        case passwordBusy

        var errorDescription: String? {
            switch self {
            case .missingFields: "请填写别名和登录邮箱或手机号。"
            case .removedAccount: "此账号已移除。请先从「最近移除」恢复。"
            case .changedAccount: "账号档案已更改，请重新打开密码设置。"
            case .passwordBusy: "正在更新此账号的密码，请稍后重试。"
            }
        }
    }

    struct RemovedAccount: Codable, Identifiable {
        let profile: AccountProfile
        let index: Int
        var deletionPending: Bool? = nil
        var id: UUID { profile.id }
    }

    enum DeletionError: LocalizedError {
        case cannotStart
        case cannotFinish
        case cannotReset

        var errorDescription: String? {
            switch self {
            case .cannotStart:
                "无法保存删除状态，未操作钥匙串。请检查存储空间和写入权限后重试。"
            case .cannotFinish:
                "钥匙串中已无此账号的密码，但档案删除尚未完成。请检查存储空间和写入权限后重试。"
            case .cannotReset:
                "未能完成钥匙串删除，且无法更新档案状态。请检查钥匙串和档案写入权限后重试。"
            }
        }
    }

    private struct Archive: Codable {
        var profiles: [AccountProfile] = []
        var lastSelectedID: UUID?
        var removed: [RemovedAccount]?
    }

    private let file: URL
    private var archive: Archive?
    private(set) var passwordRevision = 0
    private var removingIDs: Set<UUID> = []
    private var editingPasswordIDs: Set<UUID> = []

    func isRemoving(_ profile: AccountProfile) -> Bool {
        removingIDs.contains(profile.id)
    }

    func passwordDidChange() {
        passwordRevision += 1
    }

    var isLoaded: Bool { archive != nil }
    var profiles: [AccountProfile] { archive?.profiles ?? [] }
    var lastSelectedID: UUID? { archive?.lastSelectedID }
    var removedAccounts: [RemovedAccount] { archive?.removed ?? [] }

    init(file: URL = URL.applicationSupportDirectory
        .appending(path: Bundle.main.bundleIdentifier ?? "org.accountswitch.AccountSwitch", directoryHint: .isDirectory)
        .appending(path: "accounts.json", directoryHint: .notDirectory)) {
        self.file = file
        load()
    }

    func load() {
        do {
            let data = try Data(contentsOf: file)
            archive = try JSONDecoder().decode(Archive.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            archive = Archive()
        } catch {
            archive = nil
        }
    }

    func save(_ profile: AccountProfile) throws {
        let profile = profile.normalized
        guard profile.canSave else { throw ValidationError.missingFields }
        guard !editingPasswordIDs.contains(profile.id) else { throw ValidationError.passwordBusy }
        guard !removedAccounts.contains(where: { $0.id == profile.id }) else { throw ValidationError.removedAccount }
        try update { archive in
            if let index = archive.profiles.firstIndex(where: { $0.id == profile.id }) {
                archive.profiles[index] = profile
            } else {
                archive.profiles.append(profile)
            }
        }
    }

    @discardableResult
    func remove(_ profile: AccountProfile) throws -> Bool {
        guard !editingPasswordIDs.contains(profile.id) else { throw ValidationError.passwordBusy }
        var removed = false
        try update { archive in
            guard let index = archive.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
            let entry = RemovedAccount(profile: archive.profiles.remove(at: index), index: index)
            var entries = archive.removed ?? []
            entries.insert(entry, at: 0)
            archive.removed = entries
            if archive.lastSelectedID == profile.id { archive.lastSelectedID = nil }
            removed = true
        }
        return removed
    }

    func restore(_ entry: RemovedAccount) throws {
        guard !isRemoving(entry.profile) else { return }
        try update { archive in
            guard let index = archive.removed?.firstIndex(where: { $0.id == entry.id }),
                  archive.removed?[index].deletionPending != true,
                  let stored = archive.removed?.remove(at: index) else { return }
            guard !archive.profiles.contains(where: { $0.id == entry.id }) else { return }
            archive.profiles.insert(stored.profile, at: min(max(stored.index, 0), archive.profiles.count))
        }
    }

    func permanentlyRemove(
        _ entry: RemovedAccount,
        removePassword: @MainActor (AccountProfile) async throws -> Void = AccountStore.removeSavedPassword
    ) async throws {
        guard let stored = removedAccounts.first(where: { $0.id == entry.id }),
              removingIDs.insert(entry.id).inserted else { return }
        defer {
            removingIDs.remove(entry.id)
            passwordDidChange()
        }
        if stored.deletionPending != true {
            do { try setDeletionPending(true, for: stored.id) }
            catch { throw DeletionError.cannotStart }
        }
        do {
            try await removePassword(stored.profile)
        } catch {
            if stored.deletionPending != true {
                do { try setDeletionPending(nil, for: stored.id) }
                catch { throw DeletionError.cannotReset }
            }
            throw error
        }
        do {
            try update { $0.removed?.removeAll { $0.id == stored.id } }
        } catch {
            throw DeletionError.cannotFinish
        }
    }

    private static func removeSavedPassword(_ profile: AccountProfile) async throws {
        try await AccountPasswordVault.shared.remove(for: profile)
    }

    func editPassword(for profile: AccountProfile, _ update: () async throws -> Void) async throws {
        guard profiles.contains(where: { $0.id == profile.id && $0.login == profile.login })
        else { throw ValidationError.changedAccount }
        guard editingPasswordIDs.insert(profile.id).inserted else { throw ValidationError.passwordBusy }
        defer { editingPasswordIDs.remove(profile.id) }
        try await update()
    }

    private func setDeletionPending(_ pending: Bool?, for id: UUID) throws {
        try update { archive in
            if let index = archive.removed?.firstIndex(where: { $0.id == id }) {
                archive.removed?[index].deletionPending = pending
            }
        }
    }

    func select(_ profile: AccountProfile) throws {
        try update { archive in
            archive.lastSelectedID = profile.id
        }
    }

    private func update(_ change: (inout Archive) -> Void) throws {
        guard var updated = archive else { throw CocoaError(.fileReadCorruptFile) }
        change(&updated)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        archive = updated
    }
}
