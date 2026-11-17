import SwiftUI

struct AccountsWindow: View {
    @Environment(\.openWindow) private var openWindow
    let store: AccountStore
    let handoff: AppStoreHandoff
    let delegate: AccountSwitchDelegate
    @Binding var showsPreferences: Bool

    var body: some View {
        ZStack {
            AccountLibrary(store: store, handoff: handoff, isCompact: false, showsPreferences: $showsPreferences)
                .opacity(showsPreferences ? 0 : 1)
                .allowsHitTesting(!showsPreferences)
                .accessibilityHidden(showsPreferences)
            if showsPreferences { AccountPreferencesView() }
        }
        .frame(minWidth: 560, minHeight: 340)
        .onAppear {
            delegate.openAccountsWindow = { [openWindow] in
                openWindow(id: AccountSwitchApp.windowID)
            }
        }
    }
}
