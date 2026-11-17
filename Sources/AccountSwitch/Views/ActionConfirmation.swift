import SwiftUI

struct ActionConfirmation: View {
    let title: String
    let message: String
    let actionTitle: String
    var destructive = false
    let action: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var cancelFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .focused($cancelFocused)
                Button(actionTitle, role: destructive ? .destructive : nil) {
                    dismiss()
                    action()
                }
                .buttonStyle(.borderedProminent)
                .tint(destructive ? .red : .accentColor)
            }
            .padding(.top, 3)
        }
        .padding(14)
        .frame(width: 284)
        .defaultFocus($cancelFocused, true, priority: .userInitiated)
        .task { cancelFocused = true }
    }
}
