import Foundation
import Security
import Combine

/// Opt-in fix for a Keychain limitation (see CLAUDE.md "Known limitations"
/// #2): Claude Code periodically rewrites its own credentials item in
/// place, which resets that item's partition-list ACL — so a one-time
/// "Always Allow" doesn't stick, even for this app's stable, signed
/// identity. This re-applies Claude Status's trust on the item every
/// refresh cycle, before the app tries to read it itself.
///
/// The one thing this can't avoid: re-granting that trust needs proof of
/// the login keychain's own password — that's how the ACL model works,
/// with or without us. We store that password, once, in its own Keychain
/// item (created and read only by this app) and feed it to `/usr/bin/
/// security` via its stdin, never as a process argument — `security`
/// itself calls its `-k` flag "insecure" for exactly that reason (it's
/// visible to other local processes via `ps`); stdin isn't.
enum KeychainAutomation {
    private static let unlockService = "ClaudeStatus-keychain-unlock"
    private static let targetService = KeychainReader.service
    private static let targetAccount = "claude-code-user"
    /// ClaudeStatus's own Developer ID Team ID — see codesign -dv on the
    /// released app. Scoped narrowly to this one Keychain item; never
    /// generalized to "any item" (that's the whole safety argument for
    /// this feature — widening the target loses it).
    private static let teamID = "PZARL6555S"

    private static let kEnabled = "keychainAutomationEnabled"
    private static let kLastAppliedAt = "keychainAutomationLastAppliedAt"
    private static let kLastError = "keychainAutomationLastError"

    /// Default ON — this is meant to just work once a password is
    /// supplied, rather than being buried behind a settings toggle no one
    /// finds. Nothing is stored or executed until the user actually
    /// supplies a password via `storeSecret`, so "enabled" alone has no
    /// effect on its own.
    static var isEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: kEnabled) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: kEnabled) }
    }

    static var lastAppliedAt: Date? {
        UserDefaults.standard.object(forKey: kLastAppliedAt) as? Date
    }

    static var lastError: String? {
        UserDefaults.standard.string(forKey: kLastError)
    }

    static var hasStoredSecret: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unlockService,
            kSecAttrAccount as String: NSUserName(),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var item: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// Confirms `password` really is the login keychain's password by
    /// attempting to unlock it — the same check macOS itself would make.
    /// Run this before storing, so a typo fails fast with a clear message
    /// instead of silently breaking automation later.
    static func verifyLoginPassword(_ password: String) -> Bool {
        var keychain: SecKeychain?
        guard SecKeychainCopyDefault(&keychain) == errSecSuccess, let keychain else { return false }
        let bytes = Array(password.utf8)
        return bytes.withUnsafeBufferPointer { buf in
            SecKeychainUnlock(keychain, UInt32(buf.count), buf.baseAddress, true)
        } == errSecSuccess
    }

    static func storeSecret(_ password: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unlockService,
            kSecAttrAccount as String: NSUserName(),
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Removes the stored password and disables automation — forgetting
    /// the password is the user withdrawing consent, so it shouldn't
    /// silently stay "enabled" with nothing to run.
    static func forgetSecret() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unlockService,
            kSecAttrAccount as String: NSUserName(),
        ]
        SecItemDelete(query as CFDictionary)
        isEnabled = false
        UserDefaults.standard.removeObject(forKey: kLastAppliedAt)
        UserDefaults.standard.removeObject(forKey: kLastError)
    }

    private static func readSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: unlockService,
            kSecAttrAccount as String: NSUserName(),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Attributes-only existence check — never triggers a Keychain
    /// authorization prompt.
    private static func targetItemExists() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: targetService,
            kSecAttrAccount as String: targetAccount,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
        ]
        var item: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    /// Re-applies the partition list. Cheap no-op if disabled, not yet
    /// configured, or Claude Code hasn't written its item yet. Safe to
    /// call every refresh cycle — this is blocking, call off the main actor.
    @discardableResult
    static func applyFix() -> Bool {
        guard isEnabled, let password = readSecret(), targetItemExists() else { return true }

        let keychainPath = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "set-generic-password-partition-list",
            "-a", targetAccount, "-s", targetService,
            "-S", "apple-tool:,apple:,teamid:\(teamID)",
            keychainPath,
        ]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stdout

        do {
            try process.run()
        } catch {
            UserDefaults.standard.set("\(error)", forKey: kLastError)
            return false
        }

        // `security` falls back to an interactive GUI prompt if the stdin
        // password turns out to be wrong (or the item's owner/state make
        // the non-interactive path unavailable). This guarantees we never
        // hang waiting on a dialog no one asked for or is looking at.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)

        if let data = (password + "\n").data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        stdin.fileHandleForWriting.closeFile()

        process.waitUntilExit()
        watchdog.cancel()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            UserDefaults.standard.set(Date(), forKey: kLastAppliedAt)
            UserDefaults.standard.removeObject(forKey: kLastError)
            return true
        } else {
            UserDefaults.standard.set(output.isEmpty ? "security exited \(process.terminationStatus)" : output,
                                       forKey: kLastError)
            return false
        }
    }
}

/// Thin observable wrapper so both the Settings and Diagnostics panes can
/// present/mutate the same underlying state (UserDefaults + Keychain)
/// through SwiftUI bindings, without duplicating it.
@MainActor
final class KeychainAutomationModel: ObservableObject {
    @Published var isEnabled: Bool
    @Published private(set) var hasSecret: Bool
    @Published private(set) var lastAppliedAt: Date?
    @Published private(set) var lastErrorDescription: String?

    init() {
        isEnabled = KeychainAutomation.isEnabled
        hasSecret = KeychainAutomation.hasStoredSecret
        lastAppliedAt = KeychainAutomation.lastAppliedAt
        lastErrorDescription = KeychainAutomation.lastError
    }

    func refresh() {
        isEnabled = KeychainAutomation.isEnabled
        hasSecret = KeychainAutomation.hasStoredSecret
        lastAppliedAt = KeychainAutomation.lastAppliedAt
        lastErrorDescription = KeychainAutomation.lastError
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        KeychainAutomation.isEnabled = enabled
    }

    /// Returns nil on success, or a message to show the user.
    func save(password: String) -> String? {
        guard KeychainAutomation.verifyLoginPassword(password) else {
            return "That doesn't match your login password."
        }
        KeychainAutomation.storeSecret(password)
        refresh()
        Task.detached(priority: .utility) { _ = KeychainAutomation.applyFix() }
        return nil
    }

    func forget() {
        KeychainAutomation.forgetSecret()
        refresh()
    }

    var statusDescription: String {
        if let err = lastErrorDescription { return "Last attempt failed: \(err)" }
        if let at = lastAppliedAt {
            let f = RelativeDateTimeFormatter()
            f.unitsStyle = .full
            return "Applied \(f.localizedString(for: at, relativeTo: Date()))"
        }
        return hasSecret ? "Not applied yet" : "Not configured"
    }
}
