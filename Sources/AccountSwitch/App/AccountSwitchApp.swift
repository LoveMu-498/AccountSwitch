import AppKit
import SwiftUI

@main
struct AccountSwitchApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AccountSwitchDelegate
    @State private var accounts = AccountStore()
    @State private var handoff = AppStoreHandoff()
    @State private var authorization = AccountAuthorization()
    @State private var showsPreferences = false
    @AppStorage(AccountPreferences.showMenuBar) private var showMenuBar = false

    static let windowID = "accounts"

    var body: some Scene {
        Window("App Store 账号", id: Self.windowID) {
            AccountsWindow(store: accounts, handoff: handoff, delegate: delegate, showsPreferences: $showsPreferences)
                .environment(authorization)
        }
        .defaultSize(width: 660, height: 380)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("设置…") {
                    showsPreferences = true
                    delegate.openAccountsWindow?()
                    NSApp.activate()
                }
                .keyboardShortcut(",")
            }
        }

        MenuBarExtra("AccountSwitch", systemImage: "arrow.left.arrow.right", isInserted: $showMenuBar) {
            AccountLibrary(store: accounts, handoff: handoff, isCompact: true, showsPreferences: $showsPreferences)
                .environment(authorization)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AccountSwitchDelegate: NSObject, NSApplicationDelegate {
    var openAccountsWindow: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, let openAccountsWindow else { return true }
        openAccountsWindow()
        return false
    }
}
