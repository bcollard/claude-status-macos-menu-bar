import SwiftUI
import AppKit

/// Loads the credential inventory off the main actor — Keychain calls can
/// block, and an authorization prompt would freeze the Settings window.
@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published private(set) var entries: [KeychainEntryDiagnostic] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadedAt: Date?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                KeychainReader.diagnose()
            }.value
            entries = result
            loadedAt = Date()
            isLoading = false
        }
    }

    /// Plain-text dump for bug reports. Metadata only — no token material.
    var report: String {
        var lines = ["Claude Status — credential diagnostics"]
        lines.append("service: \(KeychainReader.service)")
        lines.append("entries: \(entries.count)")
        for e in entries {
            lines.append("")
            lines.append("- \(e.source.rawValue) \(e.account)\(e.isSelected ? "  [in use]" : "")")
            lines.append("  plan:     \(e.subscriptionType ?? "—")")
            lines.append("  expires:  \(Self.absolute(e.expiresAt))\(e.isExpired ? " (expired)" : "")")
            lines.append("  created:  \(Self.absolute(e.createdAt))")
            lines.append("  modified: \(Self.absolute(e.modifiedAt))")
            lines.append("  token:    \(e.hasAccessToken ? "present" : "absent")")
            if let err = e.readError { lines.append("  error:    \(err)") }
        }
        return lines.joined(separator: "\n")
    }

    static func absolute(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

/// Read-only inventory of every place Claude Status looks for credentials.
/// Deliberately has no delete affordance: deciding an entry is obsolete is
/// a judgement call with a bad failure mode (removing the live entry forces
/// a `/login`), so the destructive step stays in the user's own shell.
struct DiagnosticsView: View {
    @StateObject private var model = DiagnosticsModel()
    @StateObject private var automation = KeychainAutomationModel()
    @State private var copiedID: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(automation.isEnabled ? "Enabled" : "Disabled")
                        .foregroundStyle(automation.isEnabled ? .green : .secondary)
                    Spacer()
                    Text(automation.statusDescription)
                        .font(.caption)
                        .foregroundStyle(automation.lastErrorDescription == nil ? Color.secondary : Color.red)
                        .lineLimit(2)
                }
                if automation.hasSecret {
                    Button("Forget Stored Password") { automation.forget() }
                        .controlSize(.small)
                }
            } header: {
                Text("Keychain Automation")
            } footer: {
                Text("Re-applies this app's Keychain permission on \"\(KeychainReader.service)\" automatically. Configure in the General tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if model.entries.isEmpty {
                    Text(model.isLoading
                         ? "Reading Keychain…"
                         : "No Claude Code credentials found. Run `claude` and log in.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.entries) { entry in
                        row(entry)
                    }
                }
            } header: {
                HStack {
                    Text("Credential entries")
                    Spacer()
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    }
                }
            } footer: {
                Text("""
                     Claude Status reads these and never writes to the Keychain. \
                     It uses the entry with the latest expiry — the one marked \
                     In use. Extra entries are inert: Claude Code leaves them \
                     behind when the macOS username changes or when an older \
                     build wrote a differently-named account.

                     To remove one, copy its command and run it in Terminal. If \
                     you remove the entry Claude Code itself is writing to, \
                     you'll have to log in again.
                     """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Re-scan") { model.load() }
                        .disabled(model.isLoading)
                    Button("Copy report") {
                        copy(model.report, id: "report")
                    }
                    .disabled(model.entries.isEmpty)
                    Spacer()
                    if let at = model.loadedAt {
                        Text("Scanned \(DiagnosticsModel.absolute(at))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Tokens are never displayed or copied — the report contains metadata only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.load() }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ e: KeychainEntryDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(e.account)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                if e.isSelected { badge("In use", tint: .accentColor) }
                Spacer()
                Text(e.source.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            status(e)

            Text("Created \(DiagnosticsModel.absolute(e.createdAt)) · "
                 + "Modified \(DiagnosticsModel.absolute(e.modifiedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let plan = e.subscriptionType {
                Text("Plan \(plan.capitalized)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let cmd = e.removalCommand, !e.isSelected {
                HStack(spacing: 6) {
                    Button(copiedID == e.id ? "Copied" : "Copy removal command") {
                        copy(cmd, id: e.id)
                    }
                    .controlSize(.small)
                    Text("not used by Claude Status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func status(_ e: KeychainEntryDiagnostic) -> some View {
        if let err = e.readError {
            // Almost always the partition-list ACL: this app was never
            // authorized for that item, so its payload can't be inspected.
            label("Not readable — \(err)", systemImage: "lock.trianglebadge.exclamationmark",
                  tint: .orange)
        } else if !e.hasAccessToken {
            label("No access token in payload", systemImage: "questionmark.circle", tint: .orange)
        } else if let exp = e.expiresAt, e.isExpired {
            label("Expired \(DiagnosticsModel.relative(exp))",
                  systemImage: "xmark.circle.fill", tint: .red)
        } else if let exp = e.expiresAt {
            label("Valid until \(DiagnosticsModel.absolute(exp))",
                  systemImage: "checkmark.circle.fill", tint: .green)
        } else {
            label("No expiry in payload", systemImage: "questionmark.circle", tint: .secondary)
        }
    }

    private func label(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).imageScale(.small)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(tint)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    private func copy(_ text: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedID = id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedID == id { copiedID = nil }
        }
    }
}
