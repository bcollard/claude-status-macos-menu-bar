import SwiftUI

@main
struct ClaudeStatusApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
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
