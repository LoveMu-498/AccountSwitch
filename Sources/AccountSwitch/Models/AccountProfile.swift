import Foundation

struct AccountProfile: Codable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name = ""
    var region = ""
    var regionCode: String?
    var login = ""
    var avatarData: Data?
    var avatarEmoji: String?

    var canSave: Bool { !normalized.name.isEmpty && !normalized.login.isEmpty }

    var displayName: String {
        region.isEmpty ? name : "\(name)（\(region)）"
    }

    var normalized: Self {
        var profile = self
        profile.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.login = login.trimmingCharacters(in: .whitespacesAndNewlines)
        return profile
    }

    static func loginIcon(for value: String) -> String {
        switch loginKind(for: value) {
        case .email: "at"
        case .phone: "phone"
        case .other: "person.crop.circle"
        }
    }

    private enum LoginKind { case email, phone, other }

    private static func loginKind(for value: String) -> LoginKind {
        let login = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if login.contains("@") { return .email }
        let separators: Set<Character> = ["+", "-", "(", ")", ".", "＋", "－", "（", "）", "．"]
        if login.contains(where: \.isNumber),
           login.allSatisfy({ $0.isNumber || $0.isWhitespace || separators.contains($0) }) {
            return .phone
        }
        return .other
    }

    static func emojiAvatar(from value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count == 1, let first = candidate.unicodeScalars.first else { return nil }
        let scalars = candidate.unicodeScalars
        if (0x1F1E6...0x1F1FF).contains(first.value) {
            return scalars.count == 2 && scalars.allSatisfy { (0x1F1E6...0x1F1FF).contains($0.value) }
                ? candidate : nil
        }
        guard !scalars.contains("\u{FE0E}"), !first.properties.isEmojiModifier,
              first.properties.isEmojiPresentation ||
              (first.properties.isEmoji && scalars.contains("\u{FE0F}")) ||
              (first.properties.isEmoji && scalars.last == "\u{20E3}")
        else { return nil }
        return candidate
    }

    static func copiedLoginMessage(for value: String) -> String {
        switch loginKind(for: value) {
        case .email: "已复制登录邮箱"
        case .phone: "已复制登录手机号"
        case .other: "已复制登录账号"
        }
    }
}
