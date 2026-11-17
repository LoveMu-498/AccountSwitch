import SwiftUI

struct RemovedAccountsView: View {
    let store: AccountStore
    @Environment(AccountAuthorization.self) private var authorization
    @Environment(\.dismiss) private var dismiss
    @State private var pending: AccountStore.RemovedAccount?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("最近移除").font(.title3.weight(.semibold))
            if store.removedAccounts.isEmpty {
                Text("没有已移除的账号").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.removedAccounts) { entry in
                            HStack {
                                AccountAvatar(profile: entry.profile, size: 30)
                                Text(entry.profile.displayName).lineLimit(1)
                                Spacer()
                                if entry.deletionPending != true {
                                    Button("恢复") { restore(entry) }
                                }
                                Button(entry.deletionPending == true ? "继续删除…" : "永久删除…", role: .destructive) {
                                    pending = entry
                                }
                                    .popover(isPresented: Binding(
                                        get: { pending?.id == entry.id },
                                        set: { if !$0, pending?.id == entry.id { pending = nil } }
                                    )) {
                                        ActionConfirmation(title: "永久删除账号？",
                                                           message: "将永久删除「\(entry.profile.displayName)」和此 Mac 钥匙串中已保存的密码。",
                                                           actionTitle: "永久删除", destructive: true) {
                                            delete(entry)
                                        }
                                    }
                            }
                            .disabled(store.isRemoving(entry.profile) || authorization.isAuthenticating)
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
            Divider()
            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(22)
        .frame(width: 440)
        .interactiveDismissDisabled(authorization.isAuthenticating)
    }

    private func delete(_ entry: AccountStore.RemovedAccount) {
        Task {
            do {
                guard try await authorization.verify("永久删除「\(entry.profile.displayName)」和已保存的密码。") else { return }
                try await store.permanentlyRemove(entry)
                errorMessage = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法永久删除账号，请重试。"
            }
        }
    }

    private func restore(_ entry: AccountStore.RemovedAccount) {
        do {
            try store.restore(entry)
            errorMessage = nil
        } catch {
            errorMessage = "无法恢复账号，请重试。"
        }
    }
}
