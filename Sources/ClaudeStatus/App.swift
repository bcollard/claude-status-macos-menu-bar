import SwiftUI

@main
struct ClaudeStatusApp: App {
    @StateObject private var store: UsageStore

    init() {
        // CLI screenshot mode.
        // `--screenshot <kind> [outDir]` where kind is one of:
        //   enterprise | pro                  (App-Store marketing canvas)
        //   popup-enterprise | popup-pro      (dropdown only, transparent)
        //   settings                          (Settings window)
        //   all
        // Writes PNGs and exits without launching the menu bar.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--screenshot") {
            let kind = (i + 1 < args.count) ? args[i + 1] : "all"
            let outDir = (i + 2 < args.count) ? args[i + 2] : "docs/screenshots"
            ScreenshotMode.run(kind: kind, outDir: outDir)
        }
        _store = StateObject(wrappedValue: UsageStore())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            // Inspired by Anthropic's asterisk-flower mark; uses Apple's
            // licensed SF Symbol `asterisk` so we don't reproduce the
            // trademarked Claude logo.
            Image(systemName: "asterisk")
                .foregroundStyle(.orange)
            if store.showCountInMenuBar, let text = store.menuBarCount {
                Text(text).font(.caption.monospacedDigit())
            }
        }
    }
}
