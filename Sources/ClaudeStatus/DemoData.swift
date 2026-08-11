import Foundation

/// Anonymous fake data for App-Store / marketing screenshots.
/// No real names, orgs, or token values — invented but plausible.
@MainActor
enum DemoData {
    static func enterpriseStore() -> UsageStore {
        let s = UsageStore(demo: true)
        s.account = "Casey"
        s.email = "casey@acme.io"
        s.organizationName = "Acme Software"
        s.plan = "enterprise"
        s.rateLimitTier = "default_claude_zero"
        s.tokenExpiresAt = Date().addingTimeInterval(6 * 3600)
        s.lastRefreshed = Date()
        s.claudeProcessCount = 4
        s.claudeProcessMemoryBytes = 2_180_000_000

        s.today = UsageWindow(
            byModel: [
                "claude-opus-4-7": ModelUsage(
                    model: "claude-opus-4-7",
                    inputTokens: 1_240, outputTokens: 198_000,
                    cacheReadTokens: 4_800_000, cacheCreateTokens: 412_000,
                    messageCount: 312),
                "claude-sonnet-4-6": ModelUsage(
                    model: "claude-sonnet-4-6",
                    inputTokens: 480, outputTokens: 42_000,
                    cacheReadTokens: 320_000, cacheCreateTokens: 18_000,
                    messageCount: 28),
                "claude-haiku-4-5-20251001": ModelUsage(
                    model: "claude-haiku-4-5-20251001",
                    inputTokens: 210, outputTokens: 12_000,
                    cacheReadTokens: 78_000, cacheCreateTokens: 4_900,
                    messageCount: 41),
            ],
            sessionCount: 7, fileCount: 12
        )

        s.week = UsageWindow(
            byModel: [
                "claude-opus-4-7": ModelUsage(
                    model: "claude-opus-4-7",
                    inputTokens: 14_200, outputTokens: 1_840_000,
                    cacheReadTokens: 31_800_000, cacheCreateTokens: 6_400_000,
                    messageCount: 1_820),
                "claude-sonnet-4-6": ModelUsage(
                    model: "claude-sonnet-4-6",
                    inputTokens: 3_400, outputTokens: 380_000,
                    cacheReadTokens: 11_400_000, cacheCreateTokens: 240_000,
                    messageCount: 312),
                "claude-haiku-4-5-20251001": ModelUsage(
                    model: "claude-haiku-4-5-20251001",
                    inputTokens: 1_800, outputTokens: 140_000,
                    cacheReadTokens: 1_280_000, cacheCreateTokens: 32_000,
                    messageCount: 547),
            ],
            sessionCount: 24, fileCount: 41
        )

        s.apiUsage = UsageAPIResponse(
            rows: [
                UsageAPIRow(
                    id: "extra_usage", label: "Extra usage",
                    value: "$103.51 / $150.00", detail: "69%",
                    progress: 0.69236
                ),
                UsageAPIRow(
                    id: "omelette_promotional", label: "Promotional",
                    value: "2%", detail: nil,
                    progress: 0.0
                ),
            ],
            extraUsage: ExtraUsageInfo(
                usedDollars: 103.51,
                limitDollars: 150.00,
                utilizationPercent: 69.236
            ),
            fiveHourPercent: nil,
            weeklyPercent: nil
        )
        return s
    }

    /// Anonymous credential inventory for the Diagnostics screenshot.
    /// Deliberately shows all three interesting states at once: the live
    /// entry, a stale one left behind by an old login, and one this app was
    /// never authorized to read.
    static func diagnostics() -> [KeychainEntryDiagnostic] {
        let day: TimeInterval = 86_400
        return [
            KeychainEntryDiagnostic(
                id: "keychain:claude-code-user",
                account: "claude-code-user",
                source: .keychain,
                path: nil,
                createdAt: Date().addingTimeInterval(-45 * day),
                modifiedAt: Date().addingTimeInterval(-2 * 3600),
                expiresAt: Date().addingTimeInterval(6 * 3600),
                subscriptionType: "enterprise",
                hasAccessToken: true,
                readError: nil,
                isSelected: true
            ),
            KeychainEntryDiagnostic(
                id: "keychain:casey",
                account: "casey",
                source: .keychain,
                path: nil,
                createdAt: Date().addingTimeInterval(-210 * day),
                modifiedAt: Date().addingTimeInterval(-92 * day),
                expiresAt: Date().addingTimeInterval(-92 * day),
                subscriptionType: "pro",
                hasAccessToken: true,
                readError: nil
            ),
            KeychainEntryDiagnostic(
                id: "keychain:casey@acme.io",
                account: "casey@acme.io",
                source: .keychain,
                path: nil,
                createdAt: Date().addingTimeInterval(-180 * day),
                modifiedAt: Date().addingTimeInterval(-120 * day),
                expiresAt: nil,
                subscriptionType: nil,
                hasAccessToken: false,
                readError: "authorization denied"
            ),
        ]
    }

    static func proStore() -> UsageStore {
        let s = UsageStore(demo: true)
        s.account = "Sam"
        s.email = "sam@example.com"
        s.organizationName = nil   // Pro pseudo-org would be suppressed anyway
        s.plan = "pro"
        s.rateLimitTier = "default_claude_ai"
        s.tokenExpiresAt = Date().addingTimeInterval(7 * 3600)
        s.lastRefreshed = Date()
        s.claudeProcessCount = 2
        s.claudeProcessMemoryBytes = 980_000_000

        s.today = UsageWindow(
            byModel: [
                "claude-opus-4-7": ModelUsage(
                    model: "claude-opus-4-7",
                    inputTokens: 320, outputTokens: 18_400,
                    cacheReadTokens: 220_000, cacheCreateTokens: 14_800,
                    messageCount: 22),
                "claude-sonnet-4-6": ModelUsage(
                    model: "claude-sonnet-4-6",
                    inputTokens: 540, outputTokens: 48_200,
                    cacheReadTokens: 480_000, cacheCreateTokens: 26_400,
                    messageCount: 47),
                "claude-haiku-4-5-20251001": ModelUsage(
                    model: "claude-haiku-4-5-20251001",
                    inputTokens: 180, outputTokens: 5_200,
                    cacheReadTokens: 32_000, cacheCreateTokens: 1_800,
                    messageCount: 14),
            ],
            sessionCount: 3, fileCount: 5
        )

        s.week = UsageWindow(
            byModel: [
                "claude-opus-4-7": ModelUsage(
                    model: "claude-opus-4-7",
                    inputTokens: 1_400, outputTokens: 92_000,
                    cacheReadTokens: 1_650_000, cacheCreateTokens: 88_000,
                    messageCount: 98),
                "claude-sonnet-4-6": ModelUsage(
                    model: "claude-sonnet-4-6",
                    inputTokens: 2_100, outputTokens: 184_000,
                    cacheReadTokens: 3_400_000, cacheCreateTokens: 132_000,
                    messageCount: 218),
                "claude-haiku-4-5-20251001": ModelUsage(
                    model: "claude-haiku-4-5-20251001",
                    inputTokens: 720, outputTokens: 22_400,
                    cacheReadTokens: 188_000, cacheCreateTokens: 9_400,
                    messageCount: 64),
            ],
            sessionCount: 14, fileCount: 21
        )

        s.apiUsage = UsageAPIResponse(
            rows: [
                UsageAPIRow(
                    id: "five_hour", label: "5-hour",
                    value: "13%", detail: "resets in 4h",
                    progress: 0.13
                ),
                UsageAPIRow(
                    id: "seven_day", label: "Weekly",
                    value: "47%", detail: "resets in 3 days",
                    progress: 0.47
                ),
            ],
            extraUsage: nil,
            fiveHourPercent: 13.0,
            weeklyPercent: 47.0
        )
        return s
    }
}
