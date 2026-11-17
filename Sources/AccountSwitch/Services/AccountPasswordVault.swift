import Foundation
import Security

actor AccountPasswordVault {
    static let shared = AccountPasswordVault()

    enum Status: Equatable {
        case missing
        case saved
        case differentLogin
    }

    enum Failure: LocalizedError {
        case missing
        case differentLogin
        case ownershipConflict
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .missing:
                "请先为这个账号保存密码。"
            case .differentLogin:
                "登录标识已更改，请为新标识保存密码。"
            case .ownershipConflict:
                "钥匙串已有归属不明的同名条目，原条目已保留。"
            case .keychain:
                "无法访问本机钥匙串。请确认钥匙串已解锁后重试。"
            }
        }
    }

    private struct Ownership: Codable {
        let format: String
        let profileID: UUID
        let login: String
    }

    private struct Entry {
        let ownership: Ownership
        let reference: Data
        let marker: Data
    }

    // The user's local keychain uses the saving app's default access control list.
    // Every lookup is scoped to one keychain, service, and profile ID.
    private let service = (Bundle.main.bundleIdentifier ?? "org.accountswitch.AccountSwitch") + ".AppStore"
    private let markerFormat = "AccountSwitchPassword/v1"

    func status(for profile: AccountProfile) throws -> Status {
        let keychain = try localKeychain()
        guard let entry = try entry(for: profile, in: keychain) else { return .missing }
        return entry.ownership.login == profile.login ? .saved : .differentLogin
    }

    func password(for profile: AccountProfile) throws -> String {
        let keychain = try localKeychain()
        guard let entry = try entry(for: profile, in: keychain) else { throw Failure.missing }
        guard entry.ownership.login == profile.login else { throw Failure.differentLogin }
        var query = exactItem(entry, profile: profile, in: keychain)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data, let secret = String(data: data, encoding: .utf8), !secret.isEmpty
        else { throw Failure.keychain(errSecDecode) }
        return secret
    }

    func save(_ password: String, for profile: AccountProfile) throws {
        guard !profile.login.isEmpty, !password.isEmpty else { throw Failure.missing }
        let keychain = try localKeychain()
        let marker = try JSONEncoder().encode(Ownership(format: markerFormat, profileID: profile.id, login: profile.login))
        let values: [String: Any] = [
            kSecAttrGeneric as String: marker,
            kSecValueData as String: Data(password.utf8)
        ]
        if let entry = try entry(for: profile, in: keychain) {
            try check(SecItemUpdate(exactItem(entry, profile: profile, in: keychain) as CFDictionary, values as CFDictionary))
            return
        }
        var item = key(for: profile).merging(values) { _, new in new }
        item[kSecUseKeychain as String] = keychain
        item[kSecAttrLabel as String] = "AccountSwitch App Store"
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem { throw Failure.ownershipConflict }
        try check(status)
    }

    func remove(for profile: AccountProfile) throws {
        let keychain = try localKeychain()
        guard let entry = try entry(for: profile, in: keychain) else { return }
        let status = SecItemDelete(exactItem(entry, profile: profile, in: keychain) as CFDictionary)
        if status == errSecItemNotFound, try self.entry(for: profile, in: keychain) == nil { return }
        try check(status)
    }

    private func entry(for profile: AccountProfile, in keychain: SecKeychain) throws -> Entry? {
        var query = search(for: profile, in: keychain)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnPersistentRef as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let attributes = result as? [String: Any],
              let reference = attributes[kSecValuePersistentRef as String] as? Data,
              let marker = attributes[kSecAttrGeneric as String] as? Data,
              let ownership = try? JSONDecoder().decode(Ownership.self, from: marker),
              ownership.format == markerFormat, ownership.profileID == profile.id
        else { throw Failure.ownershipConflict }
        return Entry(ownership: ownership, reference: reference, marker: marker)
    }

    private func exactItem(_ entry: Entry, profile: AccountProfile, in keychain: SecKeychain) -> [String: Any] {
        var query = search(for: profile, in: keychain)
        query[kSecMatchItemList as String] = [entry.reference]
        query[kSecAttrGeneric as String] = entry.marker
        return query
    }

    private func search(for profile: AccountProfile, in keychain: SecKeychain) -> [String: Any] {
        var query = key(for: profile)
        query[kSecMatchSearchList as String] = [keychain]
        return query
    }

    private func localKeychain() throws -> SecKeychain {
        var keychain: SecKeychain?
        try check(SecKeychainCopyDomainDefault(.user, &keychain))
        guard let keychain else { throw Failure.keychain(errSecNoDefaultKeychain) }
        return keychain
    }

    private func key(for profile: AccountProfile) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profile.id.uuidString
        ]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }
}
