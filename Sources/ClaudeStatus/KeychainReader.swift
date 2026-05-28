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

        // Drop entries without an access token — useless to UsageAPIClient.
        let usable = candidates.filter { ($0.accessToken?.isEmpty == false) }
        let sorted = usable.sorted {
            ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast)
        }
        if let fresh = sorted.first(where: { !$0.isExpired }) { return fresh }
        if let stale = sorted.first { return stale }
        throw lastError ?? KeychainError.notFound
    }

    private static func readKeychainEntries() throws -> [ClaudeCredentials] {
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

        let entries: [[String: Any]]
        if let arr = item as? [[String: Any]] { entries = arr }
        else if let one = item as? [String: Any] { entries = [one] }
        else { throw KeychainError.decodeFailed }

        var result: [ClaudeCredentials] = []
        for entry in entries {
            guard let acct = entry[kSecAttrAccount as String] as? String else { continue }
            guard let data = try? fetchData(account: acct) else { continue }
            if let creds = parse(account: acct, data: data) {
                result.append(creds)
            }
        }
        return result
    }

    private static func readFileEntry() -> ClaudeCredentials? {
        let path = ("~/.claude/.credentials.json" as NSString).expandingTildeInPath
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
