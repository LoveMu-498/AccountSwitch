import AppKit
import Observation

@MainActor
@Observable
final class AppStoreHandoff {
    private(set) var isBusy = false
    var retryProfile: AccountProfile?
    var retryMessage: String?

    func open() async throws {
        _ = try await launch()
    }

    func switchTo(_ profile: AccountProfile, allowSignOut: Bool) async throws {
        switch try await AccountPasswordVault.shared.status(for: profile) {
        case .missing: throw AccountPasswordVault.Failure.missing
        case .differentLogin: throw AccountPasswordVault.Failure.differentLogin
        case .saved: break
        }
        guard AppStoreLogin.isTrusted else { throw AppStoreLogin.Failure.accessibility }
        let app = try await launch()
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(8)
        while !app.isFinishedLaunching || !app.isActive {
            guard !app.isTerminated, clock.now < deadline else { throw AppStoreLogin.Failure.notReady }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await AppStoreLogin.submit(pid: app.processIdentifier, profile: profile, allowSignOut: allowSignOut)
    }

    func perform(_ action: () async throws -> Void) async throws {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        try await action()
    }

    private func launch() async throws -> NSRunningApplication {
        let workspace = NSWorkspace.shared
        let identifier = "com.apple.AppStore"
        let url = URL(filePath: "/System/Applications/App Store.app", directoryHint: .isDirectory)
        guard Bundle(url: url)?.bundleIdentifier == identifier else {
            throw CocoaError(.fileNoSuchFile)
        }
        let app = try await workspace.openApplication(at: url, configuration: .init())
        guard app.bundleIdentifier == identifier, app.bundleURL?.standardizedFileURL == url.standardizedFileURL
        else { throw CocoaError(.fileNoSuchFile) }
        return app
    }

    static func copyLogin(_ login: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(login, forType: .string)
    }
}
