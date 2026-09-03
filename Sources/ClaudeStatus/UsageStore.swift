import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published var today = UsageWindow()
    @Published var week = UsageWindow()
    @Published var account: String = "—"
    @Published var email: String?
    @Published var organizationName: String?
    @Published var plan: String?
    @Published var rateLimitTier: String?
    @Published var tokenExpiresAt: Date?
    @Published var lastRefreshed: Date?
    @Published var lastError: String?
    @Published var isRefreshing: Bool = false

    @Published var apiUsage: UsageAPIResponse?
    @Published var apiError: String?

    @Published var claudeProcessCount: Int = 0
    @Published var claudeProcessMemoryBytes: UInt64 = 0

    /// True when Keychain automation is enabled but has no password yet —
    /// drives the setup banner in the dropdown.
    @Published private(set) var keychainAutomationNeedsSetup: Bool = false

    /// True when the last `/api/oauth/usage` attempt failed (rate-limit,
    /// expired token, network error, etc.) or we're inside a 429 backoff
    /// window. Drives the red dot in the popup header.
    var apiHasIssue: Bool {
        if apiError != nil { return true }
        if let until = apiBackoffUntil, until > Date() { return true }
        if let exp = tokenExpiresAt, exp <= Date() { return true }
        return false
    }

    @Published var showCountInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showCountInMenuBar, forKey: Self.kShowCount) }
    }

    @Published var apiRefreshChoice: APIRefreshChoice {
        didSet {
            UserDefaults.standard.set(apiRefreshChoice.rawValue, forKey: Self.kApiRefresh)
            apiRefreshInterval = apiRefreshChoice.seconds
        }
    }

    private static let kShowCount = "showCountInMenuBar"
    private static let kApiRefresh = "apiRefreshChoice"

    private var timer: Timer?
    /// Local log scan cadence — cheap (just file I/O).
    var refreshInterval: TimeInterval = 60
    /// Minimum gap between `/api/oauth/usage` calls. Anthropic rate-limits
    /// this endpoint aggressively (we saw HTTP 429 at the 60s cadence) and
    /// the underlying data only changes per request anyway, so polling
    /// every few minutes is plenty. Driven by `apiRefreshChoice`.
    var apiRefreshInterval: TimeInterval = APIRefreshChoice.default.seconds
    /// When set, skip API calls until this date (driven by Retry-After or
    /// our own backoff).
    private var apiBackoffUntil: Date?
    private var apiLastFetchedAt: Date?

    init(demo: Bool = false) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.kShowCount) == nil { defaults.set(true, forKey: Self.kShowCount) }
        self.showCountInMenuBar = defaults.bool(forKey: Self.kShowCount)

        let savedChoice = (defaults.string(forKey: Self.kApiRefresh))
            .flatMap(APIRefreshChoice.init(rawValue:)) ?? .default
        self.apiRefreshChoice = savedChoice
        self.apiRefreshInterval = savedChoice.seconds

        // In demo mode (screenshot generation), skip Keychain reads, file
        // scans, and timers — the caller will set published fields directly.
        if demo { return }

        loadAccount()
        Task { await refresh() }
        scheduleTimer()
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func loadAccount() {
        let info = ClaudeConfigReader.read()
        email = info?.email
        organizationName = info?.organizationName

        do {
            let creds = try KeychainReader.read()
            account = info?.displayName ?? info?.email ?? creds.account
            plan = creds.subscriptionType
            rateLimitTier = creds.rateLimitTier
            tokenExpiresAt = creds.expiresAt
        } catch {
            account = info?.email ?? "(not logged in)"
            plan = nil
            rateLimitTier = nil
            tokenExpiresAt = nil
        }
    }

    private func loadAPI(force: Bool = false) async {
        // Server-mandated backoff (429 Retry-After) is always respected
        // — hammering during a 429 just extends the lockout.
        if let until = apiBackoffUntil, until > Date() { return }
        // Time-based throttle is only for the timer; a manual refresh
        // (force=true) bypasses it so the button actually does something.
        if !force, let last = apiLastFetchedAt,
           Date().timeIntervalSince(last) < apiRefreshInterval { return }

        do {
            let creds = try KeychainReader.read()
            let resp = try await UsageAPIClient.shared.fetch(credentials: creds)
            apiUsage = resp
            apiError = nil
            apiLastFetchedAt = Date()
            apiBackoffUntil = nil
        } catch UsageAPIError.rateLimited(let retryAfter) {
            // Keep the last known good `apiUsage` visible. Back off for
            // the server-suggested duration, or default to 5 min.
            let waitFor = retryAfter ?? 5 * 60
            apiBackoffUntil = Date().addingTimeInterval(waitFor)
            apiError = "Rate-limited; retrying in \(Int(waitFor.rounded()))s"
        } catch {
            // Soft error: keep last known good apiUsage; just record the
            // message so the UI can surface it if useful.
            apiError = "\(error)"
        }
    }

    var menuBarCount: String? {
        guard lastRefreshed != nil else { return nil }
        // 1. Enterprise w/ overage credits: "<util%> • $<used>"
        if let xu = apiUsage?.extraUsage {
            return String(format: "%.0f%% • $%.2f", xu.utilizationPercent, xu.usedDollars)
        }
        // 2. Pro/Max: "5h X% • wk Y%" (whichever buckets are populated)
        let five = apiUsage?.fiveHourPercent
        let week = apiUsage?.weeklyPercent
        switch (five, week) {
        case let (.some(f), .some(w)):
            return String(format: "5h %.0f%% • wk %.0f%%", f, w)
        case let (.some(f), .none):
            return String(format: "5h %.0f%%", f)
        case let (.none, .some(w)):
            return String(format: "wk %.0f%%", w)
        case (.none, .none):
            break
        }
        // 3. Fallback: today's local-log token total.
        let n = today.grandTotal
        guard n > 0 else { return nil }
        return formatTokens(n)
    }

    func refresh(manual: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Re-grant this app's Keychain trust *before* reading the item
        // ourselves below, so a reset since the last cycle never causes
        // our own read to trigger the OS prompt.
        _ = await Task.detached(priority: .utility) {
            KeychainAutomation.applyFix()
        }.value
        keychainAutomationNeedsSetup = KeychainAutomation.isEnabled && !KeychainAutomation.hasStoredSecret

        let cal = Calendar.current
        let now = Date()
        let startOfDay = cal.startOfDay(for: now)
        let startOfWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? startOfDay

        do {
            async let todayTask: UsageWindow = Task.detached(priority: .utility) {
                try SessionLogScanner.scan(since: startOfDay)
            }.value
            async let weekTask: UsageWindow = Task.detached(priority: .utility) {
                try SessionLogScanner.scan(since: startOfWeek)
            }.value
            let (t, w) = try await (todayTask, weekTask)
            today = t
            week = w
            lastError = nil
            lastRefreshed = Date()
        } catch {
            lastError = "\(error)"
        }

        loadAccount()
        await loadAPI(force: manual)

        let procInfo: ClaudeProcessInfo = await Task.detached(priority: .utility) {
            ProcessScanner.scanClaudeProcesses()
        }.value
        claudeProcessCount = procInfo.count
        claudeProcessMemoryBytes = procInfo.totalRSSBytes
    }
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}
