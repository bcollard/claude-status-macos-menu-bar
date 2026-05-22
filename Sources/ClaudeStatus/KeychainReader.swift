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

    /// Claude Code may leave multiple entries under the same service name
    /// (older logins under acct=<username>, newer SSO logins under
    /// acct=<email>, plus transitional acct=claude-code-user entries).
    ///
    /// We do a two-step query because macOS returns `errSecParam (-50)` when
    /// `kSecMatchLimitAll` is combined with `kSecReturnData: true`:
    ///   1. List all matching entries with attributes only (sorted by mdat).
    ///   2. For each, freshest first, fetch the data via a single-account
    ///      query and parse. Return the first non-expired one. If none are
    ///      valid, fall back to the freshest parseable entry so the UI can
    ///      still show identity + plan.
    static func read() throws -> ClaudeCredentials {
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(listQuery as CFDictionary, &item)
        if status == errSecItemNotFound { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.status(status) }

        let entries: [[String: Any]]
        if let arr = item as? [[String: Any]] { entries = arr }
        else if let one = item as? [String: Any] { entries = [one] }
        else { throw KeychainError.decodeFailed }

        let sorted = entries.sorted {
            let da = ($0[kSecAttrModificationDate as String] as? Date) ?? .distantPast
            let db = ($1[kSecAttrModificationDate as String] as? Date) ?? .distantPast
            return da > db
        }

        var fallback: ClaudeCredentials?
        var lastError: Error?
        for entry in sorted {
            guard let acct = entry[kSecAttrAccount as String] as? String else { continue }
            do {
                let data = try fetchData(account: acct)
                guard let creds = parse(account: acct, data: data) else { continue }
                if !creds.isExpired { return creds }
                if fallback == nil { fallback = creds }
            } catch {
                lastError = error
            }
        }
        if let f = fallback { return f }
        throw lastError ?? KeychainError.notFound
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
