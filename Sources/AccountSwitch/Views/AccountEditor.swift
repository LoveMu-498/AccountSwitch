import SwiftUI
import UniformTypeIdentifiers

struct AccountEditor: View {
    @Environment(AccountAuthorization.self) private var authorization
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AccountProfile
    private let original: AccountProfile?
    private let store: AccountStore
    private let onSave: (AccountProfile, Bool) -> Void
    private let onRemove: (AccountProfile) -> Void
    @State private var errorMessage: String?
    @FocusState private var focused: Field?
    @State private var confirmingRemoval = false
    @State private var pickingImage = false
    @State private var choosingAvatar = false
    @State private var avatarCrop: AvatarCropRequest?
    @State private var avatarDropTargeted = false
    @State private var avatarImportID: UUID?
    @State private var avatarImportTask: Task<Void, Never>?
    @State private var avatarProviderProgress: Progress?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case name, login }

    private struct AvatarCropRequest {
        let id = UUID()
        let image: CGImage
        let editingSavedAvatar: Bool
    }

    init(profile: AccountProfile?, store: AccountStore, onRemove: @escaping (AccountProfile) -> Void,
         onSave: @escaping (AccountProfile, Bool) -> Void) {
        original = profile
        self.store = store
        self.onSave = onSave
        self.onRemove = onRemove
        _draft = State(initialValue: profile ?? AccountProfile())
    }

    var body: some View {
        Group {
            if let avatarCrop {
                VStack(spacing: 0) {
                    AccountAvatarCrop(image: avatarCrop.image, editingSavedAvatar: avatarCrop.editingSavedAvatar,
                                      cancel: { self.avatarCrop = nil }) { data in
                        draft.avatarData = data
                        draft.avatarEmoji = nil
                        self.avatarCrop = nil
                        choosingAvatar = false
                        errorMessage = nil
                    }
                    .id(avatarCrop.id)
                    if let errorMessage { errorLabel(errorMessage).padding(.bottom, 16) }
                }
            } else {
                form
            }
        }
        .frame(width: 440)
        .contentShape(Rectangle())
        .overlay { if avatarDropTargeted && avatarImportID == nil && !authorization.isAuthenticating { avatarDropOverlay } }
        .onDrop(of: [.fileURL, .image], isTargeted: $avatarDropTargeted, perform: acceptAvatarDrop)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: avatarDropTargeted)
        .fileImporter(isPresented: $pickingImage, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result, let request = beginAvatarImport() else { return }
            loadAvatar(request) { try await AvatarImageLoader.shared.load(from: url) }
        }
        .onDisappear {
            avatarImportID = nil
            avatarProviderProgress?.cancel()
            avatarProviderProgress = nil
            avatarImportTask?.cancel()
            avatarImportTask = nil
        }
    }

    private var avatarDropOverlay: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return Label("拖放图片以更换头像", systemImage: "tray.and.arrow.down")
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: shape)
            .overlay { shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4])) }
            .padding(8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func acceptAvatarDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first, let request = beginAvatarImport() else { return false }
        let complete: @Sendable (URL?) -> Void = { url in
            let file = Result {
                guard let url else { throw AvatarImageLoader.Failure.unreadable }
                return try AvatarImageLoader.openImageFile(url)
            }
            Task { @MainActor in
                guard avatarImportID == request else { return }
                avatarProviderProgress = nil
                loadAvatar(request) { try await AvatarImageLoader.shared.load(from: file.get()) }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                complete(url)
            }
        } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            avatarProviderProgress = provider.loadFileRepresentation(forTypeIdentifier: type) { url, _ in
                complete(url)
            }
        } else {
            avatarImportID = nil
            return false
        }
        return true
    }

    private func beginAvatarImport() -> UUID? {
        guard !authorization.isAuthenticating, avatarImportID == nil else { return nil }
        let request = UUID()
        avatarImportID = request
        errorMessage = nil
        return request
    }

    private func loadAvatar(_ request: UUID, using load: @escaping @Sendable () async throws -> CGImage) {
        avatarImportTask = Task {
            defer {
                if avatarImportID == request {
                    avatarImportID = nil
                    avatarImportTask = nil
                }
            }
            do {
                let image = try await load()
                guard !Task.isCancelled, avatarImportID == request else { return }
                cropAvatar(image)
            } catch {
                guard !Task.isCancelled, avatarImportID == request else { return }
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? AvatarImageLoader.Failure.unreadable.errorDescription
            }
        }
    }

    private func cropAvatar(_ image: CGImage?, editingSavedAvatar: Bool = false) {
        guard let image else {
            errorMessage = "无法读取这张图片，请换一张。"
            return
        }
        errorMessage = nil
        avatarCrop = AvatarCropRequest(image: image, editingSavedAvatar: editingSavedAvatar)
    }

    private func editCurrentAvatar() {
        guard let data = draft.avatarData else { return }
        cropAvatar(AccountAvatar.loadImage(from: data), editingSavedAvatar: true)
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.callout)
            .foregroundStyle(.red)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 11) {
                Button(action: toggleAvatarPicker) { AccountAvatar(profile: draft) }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel("头像")
                    .accessibilityHint("更换头像")
                    .accessibilityValue(choosingAvatar ? "已展开" : "已收起")
                Text(original == nil ? "添加账号" : "编辑账号").font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                Button("更换头像", systemImage: "face.smiling", action: toggleAvatarPicker)
                    .accessibilityValue(choosingAvatar ? "已展开" : "已收起")
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 7))
                    .help("将图片拖到此窗口以更换头像")
                    .accessibilityHidden(true)
            }
            if choosingAvatar {
                AccountAvatarPicker(profile: $draft, isExpanded: $choosingAvatar,
                                    chooseImage: { pickingImage = true }, editImage: editCurrentAvatar)
                    .disabled(avatarImportID != nil)
            }

            VStack(alignment: .leading, spacing: 14) {
                field("别名", example: "例如：个人", icon: "person", value: $draft.name, focus: .name)
                field("登录邮箱或手机号", example: "name@example.com", icon: AccountProfile.loginIcon(for: draft.login),
                      value: $draft.login, focus: .login)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("国家与地区").fontWeight(.medium)
                        Text("可选").font(.caption).foregroundStyle(.secondary)
                    }
                    StorefrontPicker(region: $draft.region, regionCode: $draft.regionCode)
                }
            }
            if let errorMessage {
                errorLabel(errorMessage)
            }
            Divider()
            HStack(spacing: 8) {
                if original != nil {
                    Button(role: .destructive) { confirmingRemoval = true } label: {
                        Label("移除账号…", systemImage: "trash")
                    }
                    .popover(isPresented: $confirmingRemoval) {
                        if let original {
                            ActionConfirmation(title: "移除「\(original.displayName)」？",
                                               message: "账号将移到「最近移除」，可恢复账号和已保存的密码。",
                                               actionTitle: "移除", destructive: true, action: remove)
                        }
                    }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                if original == nil {
                    Button("仅保存账号") { save(setPassword: false) }
                        .disabled(!draft.canSave)
                }
                Button(original == nil ? "保存并设置密码" : "保存") { save(setPassword: original == nil) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!draft.canSave)
            }
        }
        .padding(22)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: draft.canSave)
        .defaultFocus($focused, original == nil ? .name : .login)
        .disabled(authorization.isAuthenticating)
        .interactiveDismissDisabled(authorization.isAuthenticating)
    }

    private func toggleAvatarPicker() {
        choosingAvatar.toggle()
    }

    private func save(setPassword: Bool) {
        do {
            try store.save(draft)
            onSave(draft.normalized, setPassword)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法保存账号，请重试。"
        }
    }

    private func remove() {
        guard let original else { return }
        Task {
            do {
                guard try await authorization.verify("将「\(original.displayName)」移到最近移除。") else { return }
                if try store.remove(original) { onRemove(original) }
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "无法移除账号，请重试。"
            }
        }
    }

    private func field(_ title: String, example: String, icon: String, value: Binding<String>, focus: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.medium)
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(title, text: value, prompt: Text(example))
                    .labelsHidden()
                    .accessibilityLabel(Text(title))
                    .textFieldStyle(.plain)
                    .focused($focused, equals: focus)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
        }
    }
}
