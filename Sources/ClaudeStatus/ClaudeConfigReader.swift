import Foundation

/// Identity info Claude Code persists in ~/.claude.json under `oauthAccount`.
/// Populated after a successful login; cleared on logout.
struct ClaudeAccountInfo: Sendable {
    let email: String?
    let displayName: String?
    let organizationName: String?
    let organizationRole: String?
    let billingType: String?
}

enum ClaudeConfigReader {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude.json")

    static func read() -> ClaudeAccountInfo? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oa = obj["oauthAccount"] as? [String: Any] else { return nil }
        return ClaudeAccountInfo(
            email: oa["emailAddress"] as? String,
            displayName: oa["displayName"] as? String,
            organizationName: oa["organizationName"] as? String,
            organizationRole: oa["organizationRole"] as? String,
            billingType: oa["billingType"] as? String
        )
    }
}
