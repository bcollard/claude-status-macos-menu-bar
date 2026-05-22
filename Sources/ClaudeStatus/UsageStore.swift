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

    @Published var showCountInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showCountInMenuBar, forKey: Self.kShowCount) }
    }

    private static let kShowCount = "showCountInMenuBar"

    private var timer: Timer?
    var refreshInterval: TimeInterval = 60

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.kShowCount) == nil { defaults.set(true, forKey: Self.kShowCount) }
        self.showCountInMenuBar = defaults.bool(forKey: Self.kShowCount)

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

    private func loadAPI() async {
        do {
            let creds = try KeychainReader.read()
            let resp = try await UsageAPIClient.shared.fetch(credentials: creds)
            apiUsage = resp
            apiError = nil
        } catch {
            apiUsage = nil
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

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
        await loadAPI()
    }
}

func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}
