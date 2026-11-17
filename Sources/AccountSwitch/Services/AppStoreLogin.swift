import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

enum AppStoreLogin {
    enum Failure: LocalizedError {
        case accessibility
        case signInUnavailable
        case notReady
        case storeWelcome
        case signedIn
        case signOutDidNotSettle
        case unsupportedForm
        case differentAccountAtPasswordStep
        case existingInput
        case unexpectedStep
        case authenticationFailed(AuthenticationFailure)
        case verificationRequired
        case stillSignedOut
        case submissionUnknown
        case passwordCleanupUnconfirmed(String)

        var canRetryFromManager: Bool {
            switch self {
            case .notReady, .signInUnavailable, .storeWelcome, .signOutDidNotSettle: true
            default: false
            }
        }

        var errorDescription: String? {
            switch self {
            case .accessibility:
                "自动填写需要辅助功能授权。"
            case .signInUnavailable:
                "App Store 已打开，但登录窗口还不可用。请在 App Store 关闭其他弹窗，或打开「登录」，然后重试。"
            case .notReady:
                "App Store 已打开。请确认它的窗口已显示，然后点「重试切换」。"
            case .storeWelcome:
                "App Store 正在显示欢迎页面。请在 App Store 中处理后再重试。"
            case .signedIn:
                "App Store 当前已登录。"
            case .signOutDidNotSettle:
                "App Store 尚未完成退出登录。请检查当前登录状态，再切换账号。"
            case .unsupportedForm:
                "无法识别当前 App Store 弹窗的登录结构。请在 App Store 中继续。"
            case .differentAccountAtPasswordStep:
                "App Store 已进入另一个账号的密码步骤。请返回账号输入步骤后重试。"
            case .existingInput:
                "当前登录窗口已有密码。请在 App Store 中继续，或取消后再切换。"
            case .unexpectedStep:
                "无法继续自动填写。请在 App Store 中查看当前步骤。"
            case .authenticationFailed(.unknown):
                "App Store 返回「发生未知错误」，登录未完成。请在 App Store 中重试。"
            case .authenticationFailed(.credentials):
                "App Store 未接受登录凭据。请核对账号和已保存的密码。"
            case .verificationRequired:
                "请在 App Store 中完成双重认证。"
            case .stillSignedOut:
                "登录请求已提交，App Store 仍显示未登录。请在 App Store 中查看结果。"
            case .submissionUnknown:
                "尚未确认 App Store 的登录结果，请在 App Store 中查看。"
            case .passwordCleanupUnconfirmed(let message):
                "\(message) 请在 App Store 中清空密码框或关闭登录窗口。"
            }
        }
    }

    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    private static let logger = Logger(subsystem: "org.accountswitch.AccountSwitch", category: "AppStoreLogin")

    static func submit(pid: pid_t, profile: AccountProfile, allowSignOut: Bool) async throws {
        guard isTrusted else { throw Failure.accessibility }
        let app = Element(AXUIElementCreateApplication(pid))
        _ = AXUIElementSetMessagingTimeout(app.raw, 0.5)
        logger.notice("Finding App Store sign-in form")
        let initial = try await discoverForm(in: app, allowSignOut: allowSignOut)
        guard initial.purpose.acceptsCredentials else { throw Failure.unsupportedForm }
        let secret = try await AccountPasswordVault.shared.password(for: profile)
        try Task.checkCancellation()

        guard let current = form(in: app), current.sheet == initial.sheet, current.purpose.acceptsCredentials
        else { throw Failure.unexpectedStep }

        if current.password == nil {
            let accountStep = try await prepareAccount(profile.login, in: current, app: app)
            guard accountStep.primary.press() == .success else { throw Failure.unexpectedStep }
            logger.notice("Submitted the account identifier")
        } else if current.login.text(kAXValueAttribute) != profile.login {
            throw Failure.differentAccountAtPasswordStep
        }

        guard let passwordStep = try await waitForForm(in: app, matching: {
            $0.window == current.window && $0.purpose.acceptsCredentials &&
                $0.password != nil && $0.login.text(kAXValueAttribute) == profile.login
        }), let field = passwordStep.password
        else { throw Failure.unexpectedStep }
        logger.notice("Verified password step for the selected account")
        guard passwordStep.primary.enabled == false,
              field.text(kAXValueAttribute)?.isEmpty != false else { throw Failure.existingInput }
        try Task.checkCancellation()
        guard field.setValue(""), let cleared = form(in: app),
              cleared.matches(passwordStep, account: profile.login),
              cleared.primary.enabled == false,
              field.text(kAXValueAttribute)?.isEmpty != false
        else { throw Failure.unexpectedStep }

        let inputBeforeFill = inputEventCount
        var didWritePassword = false
        do {
            guard field.setValue(secret) else { throw Failure.unexpectedStep }
            didWritePassword = true
            guard let ready = try await waitForForm(in: app, matching: {
                $0.matches(passwordStep, account: profile.login) && $0.primary.enabled == true
            })
            else { throw Failure.unexpectedStep }
            let value = passwordFieldValue(field.text(kAXValueAttribute), written: secret)
            let inputUnchanged = inputBeforeFill != nil && inputBeforeFill == inputEventCount
            guard value == .autofilled || ((value == .matchingMask || value == .unreadable) && inputUnchanged)
            else { throw Failure.unexpectedStep }
            try Task.checkCancellation()
            guard ready.primary.press() == .success else { throw Failure.submissionUnknown }
            logger.notice("Submitted the password once")
            try await observeLoginResult(in: app, submitted: ready, account: profile.login)
        } catch {
            if didWritePassword, let latest = form(in: app), latest.matches(passwordStep, account: profile.login) {
                let value = passwordFieldValue(field.text(kAXValueAttribute), written: secret)
                let inputUnchanged = inputBeforeFill != nil && inputBeforeFill == inputEventCount
                switch value {
                case .empty, .changed:
                    break
                case _ where canClearPassword(value, inputUnchanged: inputUnchanged) && field.setValue(""):
                    break
                case .autofilled, .matchingMask, .differentLengthMask, .unreadable:
                    throw Failure.passwordCleanupUnconfirmed(error.localizedDescription)
                }
            }
            throw error
        }
        logger.notice("App Store reported a signed-in session")
    }

    private static func prepareAccount(_ account: String, in current: Form, app: Element) async throws -> Form {
        try Task.checkCancellation()
        guard current.login.setValue(""), let cleared = form(in: app),
              cleared.hasSameFields(as: current), cleared.login.text(kAXValueAttribute)?.isEmpty != false,
              cleared.login.setValue(account),
              let ready = try await waitForForm(in: app, matching: {
                  $0.matches(current, account: account) && $0.primary.enabled == true
              })
        else { throw Failure.unexpectedStep }
        return ready
    }

    enum PasswordFieldValue { case empty, autofilled, matchingMask, differentLengthMask, changed, unreadable }

    static func passwordFieldValue(_ value: String?, written: String) -> PasswordFieldValue {
        guard let value else { return .unreadable }
        if value.isEmpty { return .empty }
        if value.utf8.elementsEqual(written.utf8) { return .autofilled }
        // App Store can expose its secure field with AppKit's private-use masking glyph.
        if value.allSatisfy({ $0 == "\u{F79A}" || $0 == "•" || $0 == "●" || $0 == "*" }) {
            return value.utf16.count == written.utf16.count ? .matchingMask : .differentLengthMask
        }
        return .changed
    }

    static func canClearPassword(_ value: PasswordFieldValue, inputUnchanged: Bool) -> Bool {
        value == .autofilled || (value == .matchingMask && inputUnchanged)
    }

    private static var inputEventCount: UInt32? {
        // Quartz uses UInt32.max for its aggregate input-event counter.
        guard let anyInput = CGEventType(rawValue: UInt32.max) else { return nil }
        return CGEventSource.counterForEventType(.combinedSessionState, eventType: anyInput)
    }

    private static func observeLoginResult(in app: Element, submitted: Form, account: String) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        var resultChanged = submitted.failure == nil
        repeat {
            try Task.checkCancellation()
            let sheets = app.elements(kAXWindowsAttribute).flatMap { $0.nestedSheets(depth: 4) }
            if sheets.contains(where: { hasVerificationPrompt($0) }) { throw Failure.verificationRequired }
            if let current = form(in: app) {
                if current.window == submitted.window, current.login.text(kAXValueAttribute) == account {
                    if let failure = current.failure, resultChanged || current.primary.enabled == false {
                        logger.notice("App Store reported an authentication error")
                        throw Failure.authenticationFailed(failure)
                    }
                    if current.failure == nil { resultChanged = true }
                }
            } else {
                resultChanged = true
                if sheets.isEmpty, storeMenuAction(in: app, titles: signOutTitles) != nil { return }
            }
            try await Task.sleep(for: .milliseconds(200))
        } while clock.now < deadline

        if storeMenuAction(in: app, titles: signInTitles) != nil { throw Failure.stillSignedOut }
        throw Failure.submissionUnknown
    }

    private static func discoverForm(in app: Element, allowSignOut: Bool) async throws -> Form {
        guard let entry = try await waitFor(timeout: .seconds(12), { discoverEntry(in: app) }) else {
            logger.notice("Timed out waiting for an App Store sign-in entry")
            throw hasOpenWindow(in: app) ? Failure.signInUnavailable : Failure.notReady
        }

        switch entry {
        case .signedIn(let signOut):
            guard allowSignOut else { throw Failure.signedIn }
            let sheets = app.elements(kAXWindowsAttribute).flatMap(\.sheets)
            guard sheets.isEmpty, signOut.press() == .success else { throw Failure.signOutDidNotSettle }
            logger.notice("Requested App Store sign-out")
            try await waitForSignedOut(in: app)
            logger.notice("Verified a stable signed-out state")
            if let existing = form(in: app) { return existing }
            guard let signIn = signInEntry(in: app) else { throw Failure.signInUnavailable }
            return try await openSignIn(signIn, in: app)
        case .form(let existing):
            return existing
        case .signIn(let action):
            return try await openSignIn(action, in: app)
        case .welcome:
            throw Failure.storeWelcome
        }
    }

    private enum Entry {
        case signedIn(Element), form(Form), signIn(Element), welcome
    }

    private static func discoverEntry(in app: Element) -> Entry? {
        let windows = openWindows(in: app)
        guard !windows.isEmpty else { return nil }
        let sheets = windows.flatMap(\.sheets)
        if sheets.flatMap(\.children).contains(where: { $0.identifier == "AppStore.onboarding.continueButton" }) {
            return .welcome
        }
        if let signOut = storeMenuAction(in: app, titles: signOutTitles) { return .signedIn(signOut) }
        if let existing = form(in: app) { return .form(existing) }
        return signInEntry(in: app).map(Entry.signIn)
    }

    private static func hasOpenWindow(in app: Element) -> Bool { !openWindows(in: app).isEmpty }

    private static func openWindows(in app: Element) -> [Element] {
        app.elements(kAXWindowsAttribute).filter { $0.role == kAXWindowRole && $0.minimized != true }
    }

    private static func openSignIn(_ action: Element, in app: Element) async throws -> Form {
        guard action.press() == .success,
              let opened = try await waitFor(timeout: .seconds(8), { form(in: app) })
        else { throw Failure.signInUnavailable }
        return opened
    }

    private static func waitForSignedOut(in app: Element) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(12)
        var signedOutSince: ContinuousClock.Instant?
        repeat {
            try Task.checkCancellation()
            if storeMenuAction(in: app, titles: signOutTitles) == nil,
               signInEntry(in: app) != nil {
                let now = clock.now
                if let since = signedOutSince {
                    if now - since >= .seconds(1) { return }
                } else {
                    signedOutSince = now
                }
            } else {
                signedOutSince = nil
            }
            try await Task.sleep(for: .milliseconds(200))
        } while clock.now < deadline
        logger.notice("Timed out waiting for a stable signed-out state")
        throw Failure.signOutDidNotSettle
    }

    private static let signInTitles = ["登录", "登入", "Sign In"]
    private static let signOutTitles = ["退出登录", "退出登入", "登出", "Sign Out"]

    private static func signInEntry(in app: Element) -> Element? {
        let sheets = app.elements(kAXWindowsAttribute).flatMap(\.sheets)
        if sheets.isEmpty { return storeMenuAction(in: app, titles: signInTitles) }
        guard sheets.count == 1, let sheet = sheets.first, sheet.sheets.isEmpty else { return nil }
        return one(sheet.descendants(depth: 8).filter {
            $0.role == kAXButtonRole && $0.identifier == "AppStore.account.AppleAccountSignIn" && $0.enabled == true
        })
    }

    private static func storeMenuAction(in app: Element, titles: [String]) -> Element? {
        guard let bar: AXUIElement = app.attribute(kAXMenuBarAttribute),
              let store = one(Element(bar).children.filter { $0.role == kAXMenuBarItemRole && ["商店", "Store"].contains($0.title) })
        else { return nil }
        return one(store.children.flatMap(\.children).filter {
            let title = $0.title.trimmingCharacters(in: CharacterSet(charactersIn: ".… "))
            return $0.role == kAXMenuItemRole && $0.enabled == true && titles.contains(title)
        })
    }

    private static func waitForForm(in app: Element, matching: (Form) -> Bool = { _ in true }) async throws -> Form? {
        try await waitFor {
            guard let current = form(in: app), matching(current) else { return nil }
            return current
        }
    }

    private static func waitFor<Value>(timeout: Duration = .seconds(4), _ read: () -> Value?) async throws -> Value? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        repeat {
            try Task.checkCancellation()
            if let value = read() { return value }
            try await Task.sleep(for: .milliseconds(100))
        } while clock.now < deadline
        return nil
    }

    private static func form(in app: Element) -> Form? {
        let sheets = app.elements(kAXWindowsAttribute).flatMap { window in
            window.nestedSheets(depth: 4).map { (window, $0) }
        }
        return one(sheets.compactMap { window, sheet -> Form? in
            let controls = sheet.children
            guard let primary = one(controls.filter {
                $0.role == kAXButtonRole && $0.identifier == "Primary Button" && signInTitles.contains($0.title)
            }), one(controls.filter { $0.role == kAXButtonRole && $0.identifier == "Cancel Button" }) != nil,
            let scroll = one(controls.filter { $0.role == kAXScrollAreaRole })
            else { return nil }
            let fields = scroll.children.filter { $0.role == kAXTextFieldRole }
            let logins = fields.filter {
                $0.subrole != kAXSecureTextFieldSubrole &&
                ["电子邮件或电话号码", "電子郵件或電話號碼", "Email or Phone Number"].contains($0.placeholder)
            }
            let passwords = fields.filter {
                $0.subrole == kAXSecureTextFieldSubrole && ["密码", "密碼", "Password"].contains($0.placeholder)
            }
            guard let login = one(logins), passwords.count <= 1, fields.count == 1 + passwords.count else { return nil }
            let titles = staticText(in: scroll.children)
            return Form(window: window, sheet: sheet, login: login, password: passwords.first, primary: primary,
                        purpose: purpose(of: titles), failure: authenticationFailure(in: titles))
        })
    }

    enum AuthenticationFailure { case unknown, credentials }

    private static func staticText(in elements: [Element]) -> [String] {
        elements.filter { $0.role == kAXStaticTextRole }
            .flatMap { [$0.title, $0.text(kAXValueAttribute) ?? "", $0.text(kAXDescriptionAttribute) ?? ""] }
    }

    static func authenticationFailure(in titles: [String]) -> AuthenticationFailure? {
        let text = titles.joined(separator: "\n").lowercased()
        if ["密码不正确", "帳號或密碼不正確", "密碼不正確", "incorrect password", "password is incorrect",
            "apple账户或密码不正确", "incorrect apple account or password"].contains(where: text.contains) {
            return .credentials
        }
        if ["发生未知错误", "發生未知錯誤", "unknown error occurred", "an unknown error"].contains(where: text.contains) {
            return .unknown
        }
        return nil
    }

    private static func hasVerificationPrompt(_ sheet: Element) -> Bool {
        let content = staticText(in: sheet.descendants(depth: 3)).joined(separator: "\n").lowercased()
        return ["输入验证码", "输入验证代码", "輸入驗證碼", "enter the verification code",
                "two-factor authentication"].contains(where: content.contains)
    }

    enum Purpose {
        case account, download, other

        var acceptsCredentials: Bool { self != .other }
    }

    static func purpose(of titles: [String]) -> Purpose {
        let headings = titles.map {
            $0.lowercased().filter { !$0.isWhitespace }
        }
        let protected = ["登录以购买", "登录以从appstore购买", "登入以購買", "登入以從appstore購買",
                         "登录以订阅", "登入以訂閱", "signintopurchase", "signintosubscribe", "signintobuy"]
        if headings.contains(where: { title in protected.contains(where: title.hasPrefix) }) { return .other }
        let downloads = ["登录以从appstore下载", "登入以從appstore下載", "signintodownload"]
        if headings.contains(where: { title in downloads.contains(where: title.hasPrefix) }) { return .download }
        let accounts = ["登录apple账户", "登入apple帳號", "登入apple帳戶", "signinwithyourappleaccount", "signintoyourappleaccount", "signinwithappleaccount"]
        if headings.contains(where: { title in accounts.contains(where: title.hasPrefix) }) { return .account }
        return .other
    }

    private static func one<Value>(_ values: [Value]) -> Value? {
        values.count == 1 ? values.first : nil
    }

    private struct Form {
        let window: Element
        let sheet: Element
        let login: Element
        let password: Element?
        let primary: Element
        let purpose: Purpose
        let failure: AuthenticationFailure?

        func hasSameFields(as original: Self) -> Bool {
            window == original.window && sheet == original.sheet && login == original.login &&
                password == original.password && purpose == original.purpose
        }

        func matches(_ original: Self, account: String) -> Bool {
            hasSameFields(as: original) && login.text(kAXValueAttribute) == account
        }
    }

    private struct Element: Equatable {
        let raw: AXUIElement

        init(_ raw: AXUIElement) { self.raw = raw }
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.raw, rhs.raw) }

        func attribute<Value>(_ name: String) -> Value? {
            var result: CFTypeRef?
            guard AXUIElementCopyAttributeValue(raw, name as CFString, &result) == .success else { return nil }
            return result as? Value
        }

        func elements(_ name: String) -> [Element] {
            let nodes: [AXUIElement] = attribute(name) ?? []
            return nodes.map(Element.init)
        }

        func text(_ name: String) -> String? { attribute(name) }
        var title: String { text(kAXTitleAttribute) ?? "" }
        var role: String? { text(kAXRoleAttribute) }
        var subrole: String? { text(kAXSubroleAttribute) }
        var identifier: String? { text(kAXIdentifierAttribute) }
        var enabled: Bool? { attribute(kAXEnabledAttribute) }
        var minimized: Bool? { attribute(kAXMinimizedAttribute) }
        var placeholder: String { text(kAXPlaceholderValueAttribute) ?? "" }
        var children: [Element] { elements(kAXChildrenAttribute) }
        var sheets: [Element] { children.filter { $0.role == kAXSheetRole } }

        func nestedSheets(depth: Int) -> [Element] {
            let direct = sheets
            return depth == 0 ? direct : direct + direct.flatMap { $0.nestedSheets(depth: depth - 1) }
        }

        func descendants(depth: Int) -> [Element] {
            [self] + (depth > 0 ? children.prefix(30).flatMap { $0.descendants(depth: depth - 1) } : [])
        }

        func press() -> AXError { AXUIElementPerformAction(raw, kAXPressAction as CFString) }

        func setValue(_ value: String) -> Bool {
            var writable = DarwinBoolean(false)
            let key = kAXValueAttribute as CFString
            return AXUIElementIsAttributeSettable(raw, key, &writable) == .success && writable.boolValue &&
                AXUIElementSetAttributeValue(raw, key, value as CFString) == .success
        }
    }
}
