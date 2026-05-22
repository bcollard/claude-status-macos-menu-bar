import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject private var launch = LaunchAtLogin.shared

    var body: some View {
        Form {
            Section("General") {
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

            Section {
                Picker("Plan usage (API)", selection: $store.apiRefreshChoice) {
                    ForEach(APIRefreshChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            } header: {
                Text("Refresh")
            } footer: {
                Text("Anthropic rate-limits the usage endpoint. Lower intervals can trigger HTTP 429; the app honors Retry-After and keeps showing the last good values.")
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
        .frame(width: 480, height: 380)
    }

    private static var versionString: String {
        let bundle = Bundle.main
        let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }
}
