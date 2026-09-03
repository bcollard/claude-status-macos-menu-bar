import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var launch = LaunchAtLogin.shared
    @StateObject private var automation = KeychainAutomationModel()
    @State private var automationPassword = ""
    @State private var automationSaveError: String?
    var screenshotMode: Bool = false

    var body: some View {
        // The screenshot renderer drives this view through ImageRenderer,
        // which has no running NSApplication and lays a TabView out blank.
        if screenshotMode {
            generalPane.frame(width: 480, height: 380)
        } else {
            TabView {
                generalPane
                    .tabItem { Label("General", systemImage: "gearshape") }
                DiagnosticsView()
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            }
            .frame(width: 520, height: 440)
        }
    }

    private var generalPane: some View {
        Form {
            Section("General") {
                if screenshotMode {
                    staticToggle("Launch at login", isOn: true)
                    staticToggle("Show token count in menu bar", isOn: true)
                } else {
                    Toggle(isOn: Binding(
                        get: { launch.isEnabled },
                        set: { launch.setEnabled($0) }
                    )) {
                        Text("Launch at login")
                    }
                    if let err = launch.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }

                    Toggle("Show token count in menu bar",
                           isOn: $store.showCountInMenuBar)
                }
            }

            Section {
                if screenshotMode {
                    staticPicker(
                        label: "Plan usage (API)",
                        value: store.apiRefreshChoice.label
                    )
                } else {
                    Picker("Plan usage (API)", selection: $store.apiRefreshChoice) {
                        ForEach(APIRefreshChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Anthropic rate-limits the usage endpoint. Lower intervals can trigger HTTP 429; the app honors Retry-After and keeps showing the last good values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if screenshotMode {
                    staticToggle("Keep Claude Code Keychain access working automatically", isOn: true)
                } else {
                    Toggle("Keep Claude Code Keychain access working automatically",
                           isOn: Binding(
                               get: { automation.isEnabled },
                               set: { automation.setEnabled($0) }
                           ))

                    if automation.isEnabled {
                        if automation.hasSecret {
                            HStack {
                                Text(automation.statusDescription)
                                    .font(.caption)
                                    .foregroundStyle(automation.lastErrorDescription == nil ? Color.secondary : Color.red)
                                    .lineLimit(2)
                                Spacer()
                                Button("Forget Stored Password") { automation.forget() }
                                    .controlSize(.small)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Enter your Mac login password once. It's stored in your Keychain, readable only by Claude Status, and used to re-grant its own Keychain permission automatically.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                SecureField("Login password", text: $automationPassword)
                                    .textFieldStyle(.roundedBorder)
                                HStack {
                                    Button("Save") {
                                        if let error = automation.save(password: automationPassword) {
                                            automationSaveError = error
                                        } else {
                                            automationSaveError = nil
                                            automationPassword = ""
                                            Task { await store.refresh(manual: true) }
                                        }
                                    }
                                    .disabled(automationPassword.isEmpty)
                                    if let error = automationSaveError {
                                        Text(error).font(.caption).foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Keychain Automation")
            } footer: {
                Text("Claude Code periodically rewrites its saved login, which normally makes macOS ask for permission again every few hours. This works around that — see the project's CLAUDE.md for exactly how, including the tradeoffs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Claude Status") {
                    Text(Self.versionString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Account") {
                    Text(store.email ?? store.account)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Plan") {
                    Text((store.plan ?? "—").capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { automation.refresh() }
    }

    @ViewBuilder
    private func staticToggle(_ label: String, isOn: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 32, height: 18)
                Circle()
                    .fill(.white)
                    .frame(width: 14, height: 14)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
            }
        }
    }

    @ViewBuilder
    private func staticPicker(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                Text(value).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.18))
            )
        }
    }

    private static var versionString: String {
        let bundle = Bundle.main
        let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
}
