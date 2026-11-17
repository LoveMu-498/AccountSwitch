import AppKit
import SwiftUI

struct AccountLibrary: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AccountAuthorization.self) private var authorization
    @AppStorage(AccountPreferences.verifyActions) private var verifyActions = true
    let store: AccountStore
    let handoff: AppStoreHandoff
    let isCompact: Bool
    @Binding var showsPreferences: Bool
    @State private var editing: Editing?
    @State private var passwordProfile: AccountProfile?
    @State private var nextPasswordProfile: AccountProfile?
    @State private var accessibilityTrusted = AppStoreLogin.isTrusted
    @State private var passwordStates: [UUID: PasswordState] = [:]
    @State private var toast: Toast?
    @State private var pendingRemoval: AccountProfile?
    @State private var pendingSwitch: SwitchRequest?
    @State private var recentlyRemoved: AccountStore.RemovedAccount?
    @State private var showsRemovedAccounts = false
    @State private var hoveringUndo = false
    @FocusState private var undoFocused: Bool
    @State private var revealedCard: UUID?
    @State private var errorMessage: String?

    private struct Editing: Identifiable {
        let id = UUID()
        let profile: AccountProfile?
    }

    private struct Toast: Identifiable {
        let id = UUID()
        let title: String
        let copiedID: UUID?
    }

    private struct PasswordState {
        let login: String
        let status: AccountPasswordVault.Status?
    }

    private struct PasswordQuery: Equatable {
        let revision: Int
        let identifiers: [UUID]
        let logins: [String]
    }

    private enum SwitchAnchor { case card, retry }

    private struct SwitchRequest {
        let profile: AccountProfile
        let anchor: SwitchAnchor
    }

    private var actionsBusy: Bool { handoff.isBusy || authorization.isAuthenticating }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 10 : 16) {
            if isCompact { header }
            library
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !isCompact, let profile = handoff.retryProfile {
                HStack {
                    Text(handoff.retryMessage ?? "App Store 已打开。").foregroundStyle(.secondary)
                    Spacer()
                    Button("重试切换") { requestSwitch(profile, anchor: .retry) }
                        .disabled(actionsBusy)
                        .popover(isPresented: switchBinding(profile, anchor: .retry)) { switchConfirmation(profile) }
                }
                .font(.callout)
            }
            if isCompact { compactFooter }
            permissionFooter
        }
        .padding(isCompact ? 14 : 24)
        .frame(width: isCompact ? 366 : nil)
        .frame(maxWidth: isCompact ? nil : 850, maxHeight: isCompact ? nil : .infinity, alignment: .topLeading)
        .frame(maxWidth: isCompact ? nil : .infinity)
        .toolbar {
            if !isCompact {
                ToolbarItemGroup(placement: .primaryAction) {
                    if !showsPreferences {
                        Button("打开 App Store", systemImage: "arrow.up.right.square") { open() }
                            .help("打开 App Store")
                            .disabled(actionsBusy)
                        if !store.removedAccounts.isEmpty { removedAccountsButton }
                        if store.isLoaded { addButton.help("添加账号") }
                    }
                    Button(showsPreferences ? "返回账号" : "设置",
                           systemImage: showsPreferences ? "chevron.left" : "gearshape") {
                        showsPreferences.toggle()
                    }
                    .help(showsPreferences ? "返回账号" : "设置")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                feedbackBanner(toast.title) { EmptyView() }
                    .allowsHitTesting(false)
                    .id(toast.id)
            } else if let entry = recentlyRemoved {
                feedbackBanner("账号已移除", announcement: "账号已移除，可以撤销。") {
                    Button("撤销") { undoRemoval(entry) }
                        .focused($undoFocused)
                        .keyboardShortcut("z")
                        .accessibilityHint("恢复\(entry.profile.displayName)")
                }
                .onHover { hoveringUndo = $0 }
                .id(entry.id)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: recentlyRemoved?.id)
        .task(id: hoveringUndo || undoFocused ? nil : recentlyRemoved?.id) {
            guard !hoveringUndo, !undoFocused, let entry = recentlyRemoved else { return }
            do {
                try await Task.sleep(for: .seconds(10))
                if recentlyRemoved?.id == entry.id { recentlyRemoved = nil }
            } catch {}
        }
        .onChange(of: store.removedAccounts.map(\.id)) {
            if let entry = recentlyRemoved, !store.removedAccounts.contains(where: { $0.id == entry.id }) {
                recentlyRemoved = nil
            }
        }
        .task(id: toast?.id) {
            guard let active = toast else { return }
            do {
                try await Task.sleep(for: .seconds(2.6))
                if toast?.id == active.id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { toast = nil }
                }
            } catch {}
        }
        .task(id: PasswordQuery(revision: store.passwordRevision, identifiers: store.profiles.map(\.id), logins: store.profiles.map(\.login))) {
            accessibilityTrusted = AppStoreLogin.isTrusted
            await refreshPasswordStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = AppStoreLogin.isTrusted
            store.passwordDidChange()
        }
        .sheet(item: $editing, onDismiss: showNextPassword) { request in
            AccountEditor(profile: request.profile, store: store, onRemove: showRemoval) { profile, configurePassword in
                if configurePassword { nextPasswordProfile = profile }
                else { showToast("账号已保存") }
            }
        }
        .sheet(item: $passwordProfile) { profile in
            AccountPasswordEditor(profile: profile, store: store) { message in
                store.passwordDidChange()
                showToast(message)
            }
        }
        .sheet(isPresented: $showsRemovedAccounts) { RemovedAccountsView(store: store) }
    }

    private func feedbackBanner<Actions: View>(_ title: String, announcement: String? = nil,
                                               @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: "checkmark.circle.fill")
            actions()
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        .padding(.bottom, 50)
        .onAppear {
            AccessibilityNotification.Announcement(announcement ?? title).post()
        }
        .transition(.opacity.combined(with: reduceMotion ? .identity : .offset(y: 5)))
    }

    private var header: some View {
        Text("App Store 账号")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var library: some View {
        if !store.isLoaded {
            ContentUnavailableView {
                Label("无法读取本机账号档案", systemImage: "exclamationmark.triangle")
            } actions: {
                Button("重试") { store.load() }
            }
            .frame(maxWidth: .infinity, maxHeight: isCompact ? nil : .infinity)
        } else if store.profiles.isEmpty {
            if isCompact {
                Label("还没有账号档案", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 5)
            } else {
                ContentUnavailableView {
                    Label("还没有账号档案", systemImage: "person.crop.rectangle.stack")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            accountScroll
        }
    }

    private var accountScroll: some View {
        let gap: CGFloat = isCompact ? 6 : 10
        return ScrollView {
            LazyVStack(spacing: gap) {
                ForEach(store.profiles) { profile in
                    card(profile)
                }
            }
        }
        .defaultScrollAnchor(.top)
        .frame(height: isCompact ? min(275, CGFloat(store.profiles.count) * (66 + gap) - gap) : nil)
        .frame(maxHeight: isCompact ? nil : .infinity, alignment: .top)
    }

    private func card(_ profile: AccountProfile) -> some View {
        let hasLogin = !profile.normalized.login.isEmpty
        let canRemove = !actionsBusy && !store.isRemoving(profile)
        let surface = RoundedRectangle(cornerRadius: isCompact ? 12 : 17)
        let shortcuts: [SwipeCardAction] = [
            .init(title: "编辑", icon: "pencil", color: .gray, action: { edit(profile) })
        ] + (hasLogin ? [.init(title: "密码", icon: "key", color: .blue, action: { passwordProfile = profile })] : [])
        return AccountSwipeCard(id: profile.id, revealedCard: $revealedCard,
                                copy: hasLogin ? { copy(profile) } : nil,
                                shortcuts: canRemove ? shortcuts : [],
                                remove: canRemove ? { pendingRemoval = profile } : nil) {
            row(profile)
                .background(.quaternary.opacity(0.34), in: surface)
        }
        .clipShape(surface)
        .contentShape(.interaction, surface)
        .popover(isPresented: Binding(
            get: { pendingRemoval?.id == profile.id },
            set: { if !$0, pendingRemoval?.id == profile.id { pendingRemoval = nil } }
        ), attachmentAnchor: .point(UnitPoint(x: 0.88, y: 0.5))) {
            ActionConfirmation(title: "移除账号？",
                               message: "「\(profile.displayName)」将移到「最近移除」，可恢复账号和密码。",
                               actionTitle: "移除", destructive: true) { remove(profile) }
        }
        .contextMenu {
            if hasLogin {
                Button("复制账号", systemImage: "document.on.document") { copy(profile) }
                Button("管理密码", systemImage: "key") { passwordProfile = profile }.disabled(actionsBusy)
            }
            Button("编辑账号", systemImage: "pencil") { edit(profile) }.disabled(actionsBusy)
            Button("移除账号…", systemImage: "trash", role: .destructive) { pendingRemoval = profile }
                .disabled(!canRemove)
        }
        .accessibilityActions {
            if hasLogin { Button("复制账号") { copy(profile) } }
            if canRemove { Button("移除账号…") { pendingRemoval = profile } }
        }
    }

    private var compactFooter: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 9) {
                Button("打开 App Store", systemImage: "arrow.up.right.square") { open() }
                    .disabled(handoff.isBusy)
                Button("管理账号…", systemImage: "slider.horizontal.3") { showManager() }
                Spacer()
                if !store.removedAccounts.isEmpty {
                    utility("最近移除", icon: "trash") { showsRemovedAccounts = true }
                }
                utility("设置", icon: "gearshape") { showManager(preferences: true) }
                utility("退出", icon: "power") { NSApp.terminate(nil) }
            }
        }
    }

    private var removedAccountsButton: some View {
        Button("最近移除", systemImage: "trash") { showsRemovedAccounts = true }
            .help("最近移除")
    }

    @ViewBuilder private var permissionFooter: some View {
        if !accessibilityTrusted {
            HStack(spacing: 6) {
                Label("未授权辅助功能，自动切换不可用", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                Button("授权辅助功能…") {
                    AppStoreLogin.requestAccessibility()
                    accessibilityTrusted = AppStoreLogin.isTrusted
                }
                .buttonStyle(.link)
                Spacer(minLength: 0)
            }
            .font(.caption2)
        }
    }

    private var addButton: some View {
        Button("添加账号", systemImage: "plus") { edit(nil) }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n")
            .disabled(actionsBusy)
    }

    private func row(_ profile: AccountProfile) -> some View {
        let hasLogin = !profile.normalized.login.isEmpty
        let copied = toast?.copiedID == profile.id
        let status = passwordStates[profile.id].flatMap { $0.login == profile.login ? $0.status : nil }
        let action: String = switch status {
        case .saved: "切换"
        case .missing: "设置密码"
        case .differentLogin: "更新密码"
        case .none: "管理密码"
        }
        return HStack(spacing: isCompact ? 7 : 10) {
            if isCompact {
                Button {
                    if hasLogin && status == .saved { requestSwitch(profile) } else { showManager() }
                } label: {
                    HStack(spacing: 7) {
                        identity(profile)
                        Spacer(minLength: 5)
                        Image(systemName: status == .saved ? "arrow.left.arrow.right" : "pencil")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(status == .saved ? "填写并尝试登录所选账号" : "打开账号管理")
                .disabled(actionsBusy || (status == .saved && !accessibilityTrusted))
                .popover(isPresented: switchBinding(profile, anchor: .card)) { switchConfirmation(profile) }
            } else {
                identity(profile)
                Spacer(minLength: 14)
            }

            if hasLogin {
                utility(copied ? "已复制账号" : "复制账号", icon: copied ? "checkmark" : "document.on.document") {
                    copy(profile)
                }
                .accessibilityHint(Text(profile.displayName))
            }
            if !isCompact {
                if hasLogin {
                    if status == .saved {
                        utility("管理密码", icon: "key") { passwordProfile = profile }
                            .accessibilityHint(Text(profile.displayName))
                            .disabled(actionsBusy)
                    }

                    utility("编辑账号", icon: "pencil") { edit(profile) }
                        .accessibilityHint(Text(profile.displayName))
                        .disabled(actionsBusy)
                }
                Button(hasLogin ? action : "补全账号", systemImage: hasLogin ? (status == .saved ? "arrow.left.arrow.right" : "key") : "pencil") {
                    if !hasLogin { edit(profile) }
                    else if status == .saved { requestSwitch(profile) }
                    else { passwordProfile = profile }
                }
                .disabled(actionsBusy || (status == .saved && !accessibilityTrusted))
                .accessibilityHint(Text(profile.displayName))
                .popover(isPresented: switchBinding(profile, anchor: .card)) { switchConfirmation(profile) }
            }
        }
        .padding(.horizontal, isCompact ? 9 : 14)
        .padding(.vertical, isCompact ? 5 : 10)
        .frame(minHeight: isCompact ? 66 : 76)
        .disabled(store.isRemoving(profile))
    }

    private func identity(_ profile: AccountProfile) -> some View {
        let recent = store.lastSelectedID == profile.id
        let login = profile.normalized.login
        return HStack(spacing: isCompact ? 9 : 12) {
            AccountAvatar(profile: profile, size: isCompact ? 29 : 42)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(profile.name)
                        .font(isCompact ? .callout.weight(.semibold) : .body.weight(.semibold))
                        .lineLimit(1)
                    if recent {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("最近选择")
                    }
                }
                HStack(spacing: 9) {
                    if !profile.region.isEmpty {
                        HStack(spacing: 4) {
                            StorefrontFlag(code: profile.regionCode ?? StorefrontCatalog.shared.regionCode(for: profile.region))
                            Text(profile.region).lineLimit(1)
                        }
                        .lineLimit(1)
                        .layoutPriority(1)
                    }
                    if login.isEmpty {
                        Label("缺少登录标识", systemImage: "exclamationmark.circle")
                            .fixedSize()
                    } else {
                        Label(login, systemImage: AccountProfile.loginIcon(for: login))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if !login.isEmpty {
                    passwordLabel(profile)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func utility(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func showManager(preferences: Bool = false) {
        showsPreferences = preferences
        openWindow(id: AccountSwitchApp.windowID)
        NSApp.activate()
    }

    @ViewBuilder private func passwordLabel(_ profile: AccountProfile) -> some View {
        if let state = passwordStates[profile.id], state.login == profile.login {
            switch state.status {
            case .saved: EmptyView()
            case .missing:
                Label("未保存密码，本账号无法自动登录", systemImage: "lock.open")
                    .foregroundStyle(.orange)
            case .differentLogin:
                Label("密码待更新，本账号无法自动登录", systemImage: "lock.open")
                    .foregroundStyle(.orange)
            case .none:
                Label("密码状态不可用", systemImage: "exclamationmark.circle")
            }
        }
    }

    private func refreshPasswordStates() async {
        var updated: [UUID: PasswordState] = [:]
        for profile in store.profiles where !profile.login.isEmpty {
            let status = try? await AccountPasswordVault.shared.status(for: profile)
            guard !Task.isCancelled else { return }
            updated[profile.id] = PasswordState(login: profile.login, status: status)
        }
        passwordStates = updated
    }

    private func showNextPassword() {
        guard let profile = nextPasswordProfile else { return }
        nextPasswordProfile = nil
        passwordProfile = profile
    }

    private func showToast(_ title: String, copiedID: UUID? = nil) {
        errorMessage = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            toast = Toast(title: title, copiedID: copiedID)
        }
    }

    private func requestSwitch(_ profile: AccountProfile, anchor: SwitchAnchor = .card) {
        guard !actionsBusy else { return }
        if verifyActions {
            approveSwitch(profile)
        } else {
            pendingSwitch = SwitchRequest(profile: profile, anchor: anchor)
        }
    }

    private func switchBinding(_ profile: AccountProfile, anchor: SwitchAnchor) -> Binding<Bool> {
        Binding(
            get: { pendingSwitch?.profile.id == profile.id && pendingSwitch?.anchor == anchor },
            set: {
                if !$0, pendingSwitch?.profile.id == profile.id, pendingSwitch?.anchor == anchor { pendingSwitch = nil }
            }
        )
    }

    private func switchConfirmation(_ profile: AccountProfile) -> some View {
        ActionConfirmation(title: "切换到「\(profile.displayName)」？",
                           message: "如果 App Store 已登录，将先退出当前账号。",
                           actionTitle: "切换") { approveSwitch(profile) }
    }

    private func approveSwitch(_ profile: AccountProfile) {
        guard !actionsBusy else { return }
        Task {
            do {
                guard try await authorization.verify("切换到「\(profile.displayName)」。如果 App Store 已登录，将先退出当前账号。")
                else { return }
                open(profile)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "此 Mac 暂时无法验证身份。"
            }
        }
    }

    private func open(_ profile: AccountProfile? = nil) {
        guard !handoff.isBusy else { return }
        let current = profile.flatMap { requested in store.profiles.first(where: { $0.id == requested.id }) }
        if let profile, current?.login != profile.login {
            handoff.retryProfile = nil
            errorMessage = "账号档案已更改，请重新选择要切换的账号。"
            return
        }
        errorMessage = nil
        toast = nil
        handoff.retryProfile = nil
        Task {
            do {
                try await handoff.perform {
                    if let current {
                        try await handoff.switchTo(current, allowSignOut: true)
                        try store.select(current)
                    } else {
                        try await handoff.open()
                    }
                }
            } catch AppStoreLogin.Failure.accessibility {
                accessibilityTrusted = false
            } catch let failure as AppStoreLogin.Failure where failure.canRetryFromManager {
                handoff.retryMessage = failure.errorDescription
                handoff.retryProfile = profile
                showManager()
            } catch AccountPasswordVault.Failure.missing {
                errorMessage = "未保存密码，无法自动登录。请保存密码，或手动登录 App Store。"
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法完成操作，请重试。"
            }
        }
    }

    private func copy(_ profile: AccountProfile) {
        errorMessage = nil
        if AppStoreHandoff.copyLogin(profile.login) {
            showToast(AccountProfile.copiedLoginMessage(for: profile.login), copiedID: profile.id)
        } else {
            toast = nil
            errorMessage = "复制失败，请重试。"
        }
    }

    private func edit(_ profile: AccountProfile?) {
        errorMessage = nil
        toast = nil
        editing = Editing(profile: profile)
    }

    private func remove(_ profile: AccountProfile) {
        guard !actionsBusy else { return }
        Task {
            do {
                guard try await authorization.verify("将「\(profile.displayName)」移到最近移除。") else { return }
                if try store.remove(profile) { showRemoval(profile) }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法移除账号，请重试。"
            }
        }
    }

    private func showRemoval(_ profile: AccountProfile) {
        errorMessage = nil
        toast = nil
        if handoff.retryProfile?.id == profile.id { handoff.retryProfile = nil }
        hoveringUndo = false
        recentlyRemoved = store.removedAccounts.first { $0.id == profile.id }
    }

    private func undoRemoval(_ entry: AccountStore.RemovedAccount) {
        do {
            try store.restore(entry)
            recentlyRemoved = nil
            showToast("账号已恢复")
        } catch {
            errorMessage = "无法恢复账号，请重试。"
        }
    }
}
