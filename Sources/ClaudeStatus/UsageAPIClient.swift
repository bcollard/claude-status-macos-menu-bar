import Foundation

/// One row of plan-aware data extracted from /api/oauth/usage.
struct UsageAPIRow: Sendable, Identifiable {
    let id: String          // stable key for SwiftUI ForEach
    let label: String
    let value: String
    let detail: String?     // optional secondary line, e.g. "Resets 2 days"
    let progress: Double?   // 0.0-1.0, drives the progress bar
}

struct ExtraUsageInfo: Sendable {
    let usedDollars: Double
    let limitDollars: Double
    let utilizationPercent: Double
}

struct UsageAPIResponse: Sendable {
    let rows: [UsageAPIRow]
    let extraUsage: ExtraUsageInfo?
    /// `five_hour.utilization` (0-100) when present — the most-current
    /// signal on Pro/Max plans.
    let fiveHourPercent: Double?
    /// `seven_day.utilization` (0-100) when present.
    let weeklyPercent: Double?
}

enum UsageAPIError: Error, CustomStringConvertible {
    case noToken
    case tokenExpired(since: Date)
    case http(status: Int, body: String)
    case transport(Error)
    case decode

    var description: String {
        switch self {
        case .noToken: return "Not signed in to Claude Code."
        case .tokenExpired(let d):
            let fmt = RelativeDateTimeFormatter()
            return "Keychain token expired \(fmt.localizedString(for: d, relativeTo: Date())). Open Claude Code to refresh."
        case .http(let s, let b):
            let snippet = b.prefix(200)
            return "API \(s): \(snippet)"
        case .transport(let e): return "Network: \(e.localizedDescription)"
        case .decode: return "Could not decode API response."
        }
    }
}

actor UsageAPIClient {
    static let shared = UsageAPIClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 30
        return URLSession(configuration: cfg)
    }()

    func fetch(credentials: ClaudeCredentials) async throws -> UsageAPIResponse {
        guard let token = credentials.accessToken, !token.isEmpty else {
            throw UsageAPIError.noToken
        }
        if credentials.isExpired, let exp = credentials.expiresAt {
            throw UsageAPIError.tokenExpired(since: exp)
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ClaudeStatus/0.1 (macOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw UsageAPIError.transport(error)
        }
        guard let http = resp as? HTTPURLResponse else { throw UsageAPIError.decode }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UsageAPIError.http(status: http.statusCode, body: body)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.decode
        }
        return Self.summarize(obj)
    }

    /// Extract human-readable rows from the /api/oauth/usage payload.
    /// Schema notes (observed 2026-05 on Enterprise):
    ///   - Top-level keys map to "usage buckets"; null = doesn't apply to this plan.
    ///   - Non-null bucket values are objects with `utilization` (0-100 percent)
    ///     and optionally `resets_at` (ISO8601 string).
    ///   - `extra_usage` (Enterprise overage) has its own richer shape with
    ///     `used_credits`, `monthly_limit`, `currency`, `is_enabled`.
    private static func summarize(_ obj: [String: Any]) -> UsageAPIResponse {
        var rows: [UsageAPIRow] = []
        var extra: ExtraUsageInfo?
        var fiveHour: Double?
        var weekly: Double?

        // Extra usage / overage credits (typical of Enterprise opt-in).
        // `used_credits` and `monthly_limit` are in minor units (cents);
        // divide by 100 for dollar amounts.
        // Rendered first so it sits above the Promotional row in the UI.
        if let xu = obj["extra_usage"] as? [String: Any],
           (xu["is_enabled"] as? Bool) == true {
            let used = ((xu["used_credits"] as? Double) ?? 0) / 100.0
            let limit = ((xu["monthly_limit"] as? Double) ?? 0) / 100.0
            let util = xu["utilization"] as? Double
            let currency = (xu["currency"] as? String) ?? ""
            let value: String
            if limit > 0 {
                value = "\(formatMoney(used, currency: currency)) / \(formatMoney(limit, currency: currency))"
            } else {
                value = formatMoney(used, currency: currency)
            }
            let detail = util.map { String(format: "%.0f%%", $0) }
            rows.append(UsageAPIRow(
                id: "extra_usage", label: "Extra usage", value: value, detail: detail,
                progress: util.map { $0 / 100.0 }
            ))
            extra = ExtraUsageInfo(
                usedDollars: used,
                limitDollars: limit,
                utilizationPercent: util ?? 0
            )
        }

        // Standard utilization buckets, in the order most useful to show.
        let buckets: [(key: String, label: String)] = [
            ("five_hour",            "5-hour"),
            ("seven_day",            "Weekly"),
            ("seven_day_opus",       "Weekly · Opus"),
            ("seven_day_sonnet",     "Weekly · Sonnet"),
            ("seven_day_oauth_apps", "Weekly · OAuth apps"),
            ("seven_day_cowork",     "Weekly · Cowork"),
            ("omelette_promotional", "Promotional"),
        ]
        for b in buckets {
            guard let dict = obj[b.key] as? [String: Any] else { continue }
            guard let util = dict["utilization"] as? Double else { continue }
            let value = String(format: "%.0f%%", util)
            let detail = relativeResetDetail(dict["resets_at"])
            rows.append(UsageAPIRow(
                id: b.key, label: b.label, value: value, detail: detail,
                progress: util / 100.0
            ))
            if b.key == "five_hour" { fiveHour = util }
            if b.key == "seven_day" { weekly = util }
        }

        return UsageAPIResponse(
            rows: rows, extraUsage: extra,
            fiveHourPercent: fiveHour, weeklyPercent: weekly
        )
    }

    private static func relativeResetDetail(_ raw: Any?) -> String? {
        let date: Date?
        if let s = raw as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        } else if let ms = raw as? Double {
            date = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            date = nil
        }
        guard let d = date else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return "resets \(f.localizedString(for: d, relativeTo: Date()))"
    }

    private static func formatMoney(_ amount: Double, currency: String) -> String {
        let symbol = currency.uppercased() == "USD" ? "$" : ""
        return String(format: "%@%.2f", symbol, amount)
    }
}
