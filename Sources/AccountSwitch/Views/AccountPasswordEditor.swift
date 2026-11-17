import SwiftUI

struct AccountPasswordEditor: View {
    let profile: AccountProfile
    let store: AccountStore
    let onChange: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var status: AccountPasswordVault.Status?
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 11) {
                Image(systemName: "key")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Store 密码").font(.title3.weight(.semibold))
                    Text(profile.displayName).foregroundStyle(.secondary)
                }
            }
            if !profile.login.isEmpty {
                Label(profile.login, systemImage: AccountProfile.loginIcon(for: profile.login))
                    .foregroundStyle(.secondary)
            }
            if status == .differentLogin {
                Text("已保存的密码属于旧登录标识，更新密码后才能自动登录。").foregroundStyle(.secondary)
            } else if status == .missing {
                Text("保存密码后，此账号才能自动登录。").foregroundStyle(.secondary)
            }
            if profile.login.isEmpty {
                Text("请先为此账号填写登录邮箱或手机号。").foregroundStyle(.secondary)
            } else if let status {
                HStack(spacing: 8) {
                    Image(systemName: "lock").foregroundStyle(.secondary).accessibilityHidden(true)
                    SecureField(status == .saved ? "新密码" : "密码", text: $password)
                        .textFieldStyle(.plain)
                        .disabled(busy)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            Divider()
            HStack {
                if status == .saved || status == .differentLogin {
                    Button("移除密码", systemImage: "trash", role: .destructive) {
                        update(message: "密码已移除") { try await AccountPasswordVault.shared.remove(for: profile) }
                    }
                    .disabled(busy)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(busy)
                if status != nil, !profile.login.isEmpty {
                    Button(status == .saved ? "更换密码" : "保存到本机钥匙串") {
                        let input = password
                        update(message: "密码已保存") { try await AccountPasswordVault.shared.save(input, for: profile) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || busy)
                }
            }
        }
        .padding(22)
        .frame(width: 440)
        .interactiveDismissDisabled(busy)
        .task { await refresh() }
    }

    private func update(message: String, _ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.editPassword(for: profile, action)
                password = ""
                dismiss()
                onChange(message)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func refresh() async {
        do {
            status = try await AccountPasswordVault.shared.status(for: profile)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
