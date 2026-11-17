import AppKit
import SwiftUI

struct AccountAvatarPicker: View {
    @Binding var profile: AccountProfile
    @Binding var isExpanded: Bool
    let chooseImage: () -> Void
    let editImage: () -> Void
    @State private var emojiRequest: UUID?

    private static let presets: [(emoji: String, name: String)] = [
        ("🐱", "猫"), ("🦊", "狐狸"), ("🐼", "熊猫"), ("🌻", "向日葵"),
        ("🌙", "月亮"), ("☕", "咖啡"), ("🎮", "游戏手柄"), ("💼", "公文包")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.emoji) { preset in
                    let selected = profile.avatarEmoji == preset.emoji
                    Button { useEmoji(preset.emoji) } label: {
                        Text(preset.emoji)
                            .font(.system(size: 23))
                            .frame(width: 34, height: 36)
                    }
                    .buttonStyle(.borderless)
                    .background(selected ? Color.accentColor.opacity(0.20) : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 9))
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            HStack(spacing: 8) {
                Button("系统表情…", systemImage: "face.smiling") { emojiRequest = UUID() }
                    .background {
                        SystemEmojiReceiver(request: emojiRequest, onSelect: useEmoji)
                            .frame(width: 2, height: 22)
                            .accessibilityHidden(true)
                    }
                Button("选择本机图片…", systemImage: "photo", action: chooseImage)
            }
            if profile.avatarData != nil || profile.avatarEmoji != nil {
                HStack(spacing: 8) {
                    if profile.avatarData != nil {
                        Button("编辑当前头像…", systemImage: "crop", action: editImage)
                    }
                    Button("恢复默认头像", systemImage: "arrow.uturn.backward") {
                        profile.avatarData = nil
                        profile.avatarEmoji = nil
                        isExpanded = false
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 12))
    }

    private func useEmoji(_ emoji: String) {
        profile.avatarEmoji = emoji
        profile.avatarData = nil
        isExpanded = false
    }
}

private struct SystemEmojiReceiver: NSViewRepresentable {
    let request: UUID?
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> Receiver { Receiver(frame: .zero) }

    func updateNSView(_ view: Receiver, context: Context) {
        view.onSelect = onSelect
        guard let request, view.lastRequest != request else { return }
        view.lastRequest = request
        Task { @MainActor in
            guard view.lastRequest == request else { return }
            view.showCharacterPanel()
        }
    }

    final class Receiver: NSTextView {
        var lastRequest: UUID?
        var onSelect: ((String) -> Void)?
        private weak var previousResponder: NSResponder?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func draw(_ dirtyRect: NSRect) {}
        override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {}

        func showCharacterPanel() {
            guard let window else { return }
            if window.firstResponder !== self { previousResponder = window.firstResponder }
            guard window.makeFirstResponder(self) else { return }
            NSApp.orderFrontCharacterPalette(nil)
        }

        override func insertText(_ insertString: Any, replacementRange: NSRange) {
            receive(insertString)
        }

        override func insertText(_ insertString: Any) {
            receive(insertString)
        }

        override func cancelOperation(_ sender: Any?) {
            window?.makeFirstResponder(previousResponder)
        }

        private func receive(_ value: Any) {
            let string = (value as? NSAttributedString)?.string ?? (value as? String)
            guard let string, let emoji = AccountProfile.emojiAvatar(from: string) else { return }
            window?.makeFirstResponder(previousResponder)
            onSelect?(emoji)
        }
    }
}
