import SwiftUI

struct AccountPreferencesView: View {
    @AppStorage(AccountPreferences.verifyActions) private var verifyActions = true
    @AppStorage(AccountPreferences.showMenuBar) private var showMenuBar = false
    @Environment(AccountAuthorization.self) private var authorization
    @State private var error: String?
    @State private var verificationChange: Task<Void, Never>?

    var body: some View {
        Form {
            Section("确认操作") {
                Toggle("切换和移除账号时验证身份", isOn: Binding(
                    get: { verifyActions },
                    set: changeVerification
                ))
                    .disabled(authorization.isAuthenticating || verificationChange != nil)
                Text("使用 Touch ID，或按 macOS 提示输入本机登录密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
                }
            }
            Section("入口") {
                Toggle("在菜单栏显示 AccountSwitch", isOn: $showMenuBar)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text("设置")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 20)
        }
        .frame(maxWidth: 570)
        .onDisappear { verificationChange?.cancel() }
    }

    private func changeVerification(_ required: Bool) {
        guard verificationChange == nil else { return }
        error = nil
        verificationChange = Task {
            defer { verificationChange = nil }
            do {
                try await authorization.setVerificationRequired(required)
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
