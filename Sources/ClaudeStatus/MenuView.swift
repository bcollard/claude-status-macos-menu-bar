import SwiftUI
import Charts

struct MenuView: View {
    @ObservedObject var store: UsageStore
    /// When true, interactive controls (Button/Toggle/ProgressView) are
    /// replaced with static SwiftUI shapes — required because ImageRenderer
    /// can't draw AppKit-backed controls outside a running NSApplication.
    var screenshotMode: Bool = false

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if store.claudeProcessCount > 0 {
                activityBlock
                Divider()
            }
            planBlock
            Divider()
            usageBlock(title: "Today", window: store.today)
            Divider()
            usageBlock(title: "This Week", window: store.week)
            if let err = store.lastError {
                Divider()
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
            if store.keychainAutomationNeedsSetup {
                Divider()
                keychainSetupBanner
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    @ViewBuilder
    private var planBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Plan").font(.subheadline.bold())
            row("Subscription", (store.plan ?? "—").capitalized)
            if let tier = store.rateLimitTier {
                row("Rate-limit tier", tier)
            }
            if let exp = store.tokenExpiresAt {
                row("Token", exp > Date() ? "valid" : "expired")
            }
            if let api = store.apiUsage, !api.rows.isEmpty {
                ForEach(api.rows) { r in
                    apiRow(r)
                }
                if let err = store.apiError {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    .padding(.top, 2)
                }
            } else if store.apiUsage != nil {
                Text("No plan-level usage data for this account.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let err = store.apiError {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
            }
        }
    }

    @ViewBuilder
    private var keychainSetupBanner: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "key.slash").foregroundStyle(.orange)
            Text("Keychain automation needs a one-time password to start working.")
                .font(.caption)
                .lineLimit(3)
            Spacer()
            if screenshotMode {
                staticPill("Set Up")
            } else {
                Button("Set Up") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var activityBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Activity").font(.subheadline.bold())
            HStack(alignment: .firstTextBaseline) {
                Text("Active sessions").foregroundStyle(.secondary)
                Spacer()
                Text("\(store.claudeProcessCount)")
                    .font(.callout.monospacedDigit())
                Text(formatBytes(store.claudeProcessMemoryBytes))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var headerSubtitle: String {
        let identity = store.email ?? store.account
        // Real orgs (e.g. "Acme Software") are useful; Pro pseudo-orgs that
        // just wrap the email (e.g. "<email>'s Organization") add noise. Fall
        // back to capitalized plan name in that case.
        if let org = store.organizationName,
           !org.lowercased().contains(identity.lowercased()) {
            return "\(identity) · \(org)"
        }
        if let plan = store.plan {
            return "\(identity) · \(plan.capitalized)"
        }
        return identity
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code Usage").font(.headline)
                Text(headerSubtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.apiHasIssue {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .help(store.apiError ?? "Can't sync with Claude API")
                    .accessibilityLabel("API sync issue")
            }
            if screenshotMode {
                Image(systemName: "arrow.clockwise").foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await store.refresh(manual: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help("Refresh now")
            }
        }
    }

    private var footer: some View {
        HStack {
            if store.isRefreshing {
                Text("Refreshing…").font(.caption2).foregroundStyle(.secondary)
            } else if screenshotMode {
                Text("Updated just now")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if let d = store.lastRefreshed {
                Text("Updated \(d.formatted(.relative(presentation: .numeric)))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if screenshotMode {
                staticPill("Options…")
                staticPill("Quit")
            } else {
                Button("Options…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    @ViewBuilder
    private func staticPill(_ label: String) -> some View {
        Text(label)
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.18))
            )
    }

    @ViewBuilder
    private func usageBlock(title: String, window: UsageWindow) -> some View {
        let models = window.byModel.values.sorted { $0.totalTokens > $1.totalTokens }
        let total = window.grandTotal
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(formatTokens(total))
                    .font(.subheadline.monospacedDigit())
                Text(Pricing.formatUSD(Pricing.cost(window)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("\(window.sessionCount) sessions · \(window.totalMessages) turns")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if !models.isEmpty {
                modelStackBar(models: models, total: total)
                modelLegend(models: models)
            }
        }
    }

    @ViewBuilder
    private func modelStackBar(models: [ModelUsage], total: Int) -> some View {
        Chart {
            ForEach(models, id: \.model) { mu in
                BarMark(
                    x: .value("Tokens", mu.totalTokens),
                    y: .value("Period", "")
                )
                .foregroundStyle(by: .value("Model", mu.shortName))
                .annotation(position: .overlay) { EmptyView() }
            }
        }
        .chartForegroundStyleScale(domain: models.map(\.shortName),
                                   range: models.map { color(for: $0.shortName) })
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }

    @ViewBuilder
    private func modelLegend(models: [ModelUsage]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(models, id: \.model) { mu in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: mu.shortName))
                        .frame(width: 7, height: 7)
                    Text(mu.shortName).font(.caption)
                    Spacer()
                    Text(formatTokens(mu.totalTokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(Pricing.formatUSD(Pricing.cost(mu)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    /// Stable per-family color so Opus is always the same hue across blocks.
    private func color(for shortName: String) -> Color {
        let lc = shortName.lowercased()
        if lc.hasPrefix("opus")   { return .orange }
        if lc.hasPrefix("sonnet") { return .blue }
        if lc.hasPrefix("haiku")  { return .green }
        return .gray
    }

    @ViewBuilder
    private func apiRow(_ r: UsageAPIRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(r.label).foregroundStyle(.secondary)
                Spacer()
                Text(r.value).monospacedDigit()
                if let d = r.detail {
                    Text(d).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            if let p = r.progress {
                progressBar(value: p)
            }
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func progressBar(value p: Double) -> some View {
        let clamped = max(0, min(1, p))
        if screenshotMode {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.18))
                    Capsule()
                        .fill(progressColor(for: p))
                        .frame(width: g.size.width * clamped)
                }
            }
            .frame(height: 6)
        } else {
            ProgressView(value: clamped)
                .progressViewStyle(.linear)
                .tint(progressColor(for: p))
        }
    }

    private func progressColor(for p: Double) -> Color {
        if p >= 0.85 { return .red }
        if p >= 0.60 { return .orange }
        return .green
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
