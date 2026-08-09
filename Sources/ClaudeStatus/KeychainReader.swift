import Foundation
import Security

enum KeychainError: Error, CustomStringConvertible {
    case notFound
    case decodeFailed
    case status(OSStatus)

    var description: String {
        switch self {
        case .notFound: return "Claude Code credentials not found in Keychain"
        case .decodeFailed: return "Could not decode Keychain payload"
        case .status(let s):
            let msg = SecCopyErrorMessageString(s, nil) as String? ?? "\(s)"
            return "Keychain error: \(msg)"
        }
    }
}

/// One credential candidate as surfaced by the read-only Diagnostics pane.
/// Deliberately carries **no token material** — only metadata a user needs
/// to decide whether an entry is stale.
struct KeychainEntryDiagnostic: Identifiable, Sendable {
    enum Source: String, Sendable {
        case keychain = "Keychain"
        case file = "File"
    }

    let id: String
    let account: String
    let source: Source
    /// Filesystem path, for `.file` entries.
    let path: String?
    let createdAt: Date?
    let modifiedAt: Date?
    let expiresAt: Date?
    let subscriptionType: String?
    let hasAccessToken: Bool
    /// Set when the payload could not be fetched or parsed — most often
    /// because this app was never authorized for that Keychain item.
    let readError: String?
    /// True for the single candidate `KeychainReader.read()` would return.
    var isSelected: Bool = false

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    /// Shell command that removes this entry. Nil for the file source and
    /// for entries with no usable account attribute.
    var removalCommand: String? {
        switch source {
        case .file:
            guard let path else { return nil }
            return "rm \(Self.shellQuote(path))"
        case .keychain:
            return "security delete-generic-password -s \(Self.shellQuote(KeychainReader.service)) "
                 + "-a \(Self.shellQuote(account))"
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct ClaudeCredentials {
    let account: String
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?
    let subscriptionType: String?
    let rateLimitTier: String?
    let scopes: [String]

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }
}

enum KeychainReader {
    static let service = "Claude Code-credentials"

    /// Canonical credential location on macOS is the Keychain (Claude
    /// Code may leave multiple entries under the same service name —
    /// older logins under acct=<username>, newer SSO under acct=<email>,
    /// transitional acct=claude-code-user). Linux/Docker/dotfile setups
    /// can leave a `~/.claude/.credentials.json` file instead; we read
    /// that as a fallback so users in those configurations aren't stuck
    /// on "(not logged in)".
    ///
    /// We do a two-step Keychain query because macOS returns
    /// `errSecParam (-50)` when `kSecMatchLimitAll` is combined with
    /// `kSecReturnData: true`:
    ///   1. List all matching entries with attributes only.
    ///   2. For each, fetch the data via a single-account query.
    ///
    /// All viable candidates (Keychain entries + file) are pooled, then
    /// we pick the one with the latest `expiresAt`. If none are still
    /// valid, the freshest expired entry is returned so the UI can show
    /// identity + plan and explain the expiration.
    static func read() throws -> ClaudeCredentials {
        var candidates: [ClaudeCredentials] = []
        var lastError: Error?

        do {
            candidates.append(contentsOf: try readKeychainEntries())
        } catch {
            lastError = error
        }
        if let fileCreds = readFileEntry() {
            candidates.append(fileCreds)
        }

        if let picked = best(candidates, credentials: { $0 }) { return picked }
        throw lastError ?? KeychainError.notFound
    }

    /// Single source of truth for "which candidate wins". Generic over the
    /// element type so `diagnose()` can rank `(id, credentials)` pairs with
    /// the exact same rule `read()` applies — the panel can never disagree
    /// with what the app actually uses.
    ///
    /// Entries without an access token are dropped (useless to
    /// `UsageAPIClient`); the rest sort by `expiresAt` descending, and the
    /// first non-expired one wins. If none are still valid we fall back to
    /// the freshest expired entry so the UI can show identity + plan and
    /// explain the expiration.
    static func best<T>(_ items: [T], credentials: (T) -> ClaudeCredentials) -> T? {
        let sorted = items
            .filter { credentials($0).accessToken?.isEmpty == false }
            .sorted {
                (credentials($0).expiresAt ?? .distantPast)
                    > (credentials($1).expiresAt ?? .distantPast)
            }
        return sorted.first(where: { !credentials($0).isExpired }) ?? sorted.first
    }

    /// Attributes-only listing. Does **not** read payloads, so it never
    /// triggers a Keychain authorization prompt.
    private static func listEntryAttributes() throws -> [[String: Any]] {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &item)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError.status(status) }

        if let arr = item as? [[String: Any]] { return arr }
        if let one = item as? [String: Any] { return [one] }
        throw KeychainError.decodeFailed
    }

    private static func readKeychainEntries() throws -> [ClaudeCredentials] {
        var result: [ClaudeCredentials] = []
        for entry in try listEntryAttributes() {
            guard let acct = entry[kSecAttrAccount as String] as? String else { continue }
            guard let data = try? fetchData(account: acct) else { continue }
            if let creds = parse(account: acct, data: data) {
                result.append(creds)
            }
        }
        return result
    }

    /// Read-only inventory of every credential candidate, for the
    /// Diagnostics pane. Never deletes or writes anything.
    ///
    /// This issues exactly the same queries `read()` already runs on every
    /// refresh, so it adds no new Keychain prompt surface — but unlike
    /// `read()` it keeps entries whose payload could not be fetched or
    /// parsed, recording the reason instead of silently skipping them.
    static func diagnose() -> [KeychainEntryDiagnostic] {
        var entries: [KeychainEntryDiagnostic] = []
        var candidates: [(id: String, creds: ClaudeCredentials)] = []

        for attrs in (try? listEntryAttributes()) ?? [] {
            let acct = attrs[kSecAttrAccount as String] as? String ?? ""
            let id = "keychain:\(acct)"
            var expiresAt: Date?
            var subscriptionType: String?
            var hasAccessToken = false
            var readError: String?

            do {
                let data = try fetchData(account: acct)
                if let creds = parse(account: acct, data: data) {
                    candidates.append((id, creds))
                    expiresAt = creds.expiresAt
                    subscriptionType = creds.subscriptionType
                    hasAccessToken = creds.accessToken?.isEmpty == false
                } else {
                    readError = "payload is not recognizable Claude OAuth JSON"
                }
            } catch {
                readError = "\(error)"
            }

            entries.append(KeychainEntryDiagnostic(
                id: id,
                account: acct.isEmpty ? "(no account)" : acct,
                source: .keychain,
                path: nil,
                createdAt: attrs[kSecAttrCreationDate as String] as? Date,
                modifiedAt: attrs[kSecAttrModificationDate as String] as? Date,
                expiresAt: expiresAt,
                subscriptionType: subscriptionType,
                hasAccessToken: hasAccessToken,
                readError: readError
            ))
        }

        let filePath = (credentialsFilePath as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: filePath) {
            let id = "file:\(filePath)"
            let creds = readFileEntry()
            if let creds { candidates.append((id, creds)) }
            let fileAttrs = try? FileManager.default.attributesOfItem(atPath: filePath)
            entries.append(KeychainEntryDiagnostic(
                id: id,
                account: (filePath as NSString).lastPathComponent,
                source: .file,
                path: filePath,
                createdAt: fileAttrs?[.creationDate] as? Date,
                modifiedAt: fileAttrs?[.modificationDate] as? Date,
                expiresAt: creds?.expiresAt,
                subscriptionType: creds?.subscriptionType,
                hasAccessToken: creds?.accessToken?.isEmpty == false,
                readError: creds == nil ? "file is not recognizable Claude OAuth JSON" : nil
            ))
        }

        let winner = best(candidates, credentials: { $0.creds })?.id
        return entries
            .map { e in
                var e = e
                e.isSelected = (e.id == winner)
                return e
            }
            .sorted { a, b in
                if a.isSelected != b.isSelected { return a.isSelected }
                return (a.modifiedAt ?? .distantPast) > (b.modifiedAt ?? .distantPast)
            }
    }

    static let credentialsFilePath = "~/.claude/.credentials.json"

    private static func readFileEntry() -> ClaudeCredentials? {
        let path = (credentialsFilePath as NSString).expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return parse(account: "credentials.json", data: data)
    }

    private static func fetchData(account: String) throws -> Data {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: AnyObject?
        let s = SecItemCopyMatching(q as CFDictionary, &item)
        guard s == errSecSuccess, let d = item as? Data else {
            throw KeychainError.status(s)
        }
        return d
    }

    private static func parse(account: String, data: Data) -> ClaudeCredentials? {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: Date?
        var subscriptionType: String?
        var rateLimitTier: String?
        var scopes: [String] = []

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        accessToken = (oauth["accessToken"] as? String) ?? (oauth["access_token"] as? String)
        refreshToken = (oauth["refreshToken"] as? String) ?? (oauth["refresh_token"] as? String)
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let s = oauth["expires_at"] as? Double {
            expiresAt = Date(timeIntervalSince1970: s)
        }
        subscriptionType = oauth["subscriptionType"] as? String
        rateLimitTier = oauth["rateLimitTier"] as? String
        scopes = (oauth["scopes"] as? [String]) ?? []

        return ClaudeCredentials(
            account: account,
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            subscriptionType: subscriptionType,
            rateLimitTier: rateLimitTier,
            scopes: scopes
        )
    }
}
