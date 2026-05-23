import SwiftUI
import AppKit

@MainActor
enum ScreenshotMode {
    /// App Store accepts 2880×1800 / 2560×1600 / 1440×900 / 1280×800 for
    /// Mac apps. We target 2880×1800 (= 1440×900 logical at 2x).
    static let canvasWidth: CGFloat = 1440
    static let canvasHeight: CGFloat = 900

    /// Render screenshots with anonymous demo data.
    ///   kind = enterprise | pro            (full-canvas App-Store gallery)
    ///        | popup-enterprise | popup-pro (just the dropdown card)
    ///        | settings                     (Settings window)
    ///        | all                          (every variant)
    static func run(kind rawKind: String, outDir: String) -> Never {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        let kinds: [String]
        switch rawKind.lowercased() {
        case "all":
            kinds = ["enterprise", "pro", "popup-enterprise", "popup-pro", "settings"]
        case let s where ["enterprise", "pro", "popup-enterprise", "popup-pro", "settings"].contains(s):
            kinds = [s]
        default:
            FileHandle.standardError.write(Data("unknown kind: \(rawKind)\n".utf8))
            exit(2)
        }

        for kind in kinds {
            switch kind {
            case "enterprise":       renderMarketing(planKey: "enterprise", outDir: outDir)
            case "pro":              renderMarketing(planKey: "pro",        outDir: outDir)
            case "popup-enterprise": renderPopup(planKey: "enterprise",     outDir: outDir)
            case "popup-pro":        renderPopup(planKey: "pro",            outDir: outDir)
            case "settings":         renderSettings(outDir: outDir)
            default: break
            }
        }

        exit(0)
    }

    // MARK: - Variants

    private static func renderMarketing(planKey: String, outDir: String) {
        let (store, copy) = planKey == "enterprise"
            ? (DemoData.enterpriseStore(), ScreenshotCopy.enterprise)
            : (DemoData.proStore(),        ScreenshotCopy.pro)

        for scheme: ColorScheme in [.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            let outURL = URL(fileURLWithPath: outDir)
                .appendingPathComponent("claude-status-\(planKey)-\(suffix).png")

            let layout = ScreenshotLayout(
                scheme: scheme,
                menuBarText: store.menuBarCount ?? "",
                copy: copy
            ) {
                MenuView(store: store, screenshotMode: true)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .environment(\.colorScheme, scheme)

            writePNG(view: layout, to: outURL, opaque: true)
        }
    }

    private static func renderPopup(planKey: String, outDir: String) {
        let store = planKey == "enterprise"
            ? DemoData.enterpriseStore()
            : DemoData.proStore()

        for scheme: ColorScheme in [.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            let outURL = URL(fileURLWithPath: outDir)
                .appendingPathComponent("popup-\(planKey)-\(suffix).png")

            // Pure card on transparent background, generous margin to fit
            // the drop shadow without clipping. Used in the website hero.
            let view = MenuView(store: store, screenshotMode: true)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(scheme == .dark
                              ? Color(white: 0.16)
                              : Color(white: 0.995))
                        .shadow(color: .black.opacity(0.28),
                                radius: 28, x: 0, y: 14)
                )
                .padding(40)
                .environment(\.colorScheme, scheme)

            writePNG(view: view, to: outURL, opaque: false)
        }
    }

    private static func renderSettings(outDir: String) {
        let store = DemoData.enterpriseStore()
        for scheme: ColorScheme in [.light, .dark] {
            let suffix = scheme == .light ? "light" : "dark"
            let outURL = URL(fileURLWithPath: outDir)
                .appendingPathComponent("settings-\(suffix).png")

            // SwiftUI `Form { ... }.formStyle(.grouped)` collapses to a
            // blank rectangle through ImageRenderer (it needs a running
            // NSApplication to lay out). Hand-roll the grouped look from
            // primitives instead.
            let view = StaticSettingsView(store: store, scheme: scheme)
                .padding(40)
                .environment(\.colorScheme, scheme)

            writePNG(view: view, to: outURL, opaque: false)
        }
    }

    // MARK: - Renderer plumbing

    private static func writePNG<V: View>(view: V, to outURL: URL, opaque: Bool) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = opaque

        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed for \(outURL.path)\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: outURL)
            print("→ \(outURL.path) (\(rep.pixelsWide)×\(rep.pixelsHigh), \(png.count) bytes)")
        } catch {
            FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
            exit(1)
        }
    }
}

/// Hand-rolled mimic of `SettingsView` for ImageRenderer (Form/.grouped
/// renders blank without a running NSApplication).
private struct StaticSettingsView: View {
    let store: UsageStore
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            section(header: "General") {
                row { Text("Launch at login") } trailing: { toggle(on: true) }
                divider
                row { Text("Show token count in menu bar") } trailing: { toggle(on: true) }
            }

            sectionWithFooter(
                header: "Refresh",
                footer: "Anthropic rate-limits the usage endpoint. Lower intervals can trigger HTTP 429; the app honors Retry-After and keeps showing the last good values."
            ) {
                row { Text("Plan usage (API)") } trailing: {
                    pillPicker(value: store.apiRefreshChoice.label)
                }
            }

            section(header: "About") {
                row { Text("Claude Status") } trailing: {
                    Text("v0.1.0 (1)").monospacedDigit().foregroundStyle(.secondary)
                }
                divider
                row { Text("Account") } trailing: {
                    Text(store.email ?? store.account).foregroundStyle(.secondary)
                }
                divider
                row { Text("Plan") } trailing: {
                    Text((store.plan ?? "—").capitalized).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 480)
        .padding(.vertical, 28)
        .padding(.horizontal, 28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(scheme == .dark
                      ? Color(red: 0.13, green: 0.13, blue: 0.14)
                      : Color(red: 0.94, green: 0.94, blue: 0.96))
                .shadow(color: .black.opacity(0.25), radius: 26, x: 0, y: 12)
        )
    }

    @ViewBuilder
    private func section<Content: View>(header: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.headline)
            VStack(spacing: 0) { content() }
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(scheme == .dark
                              ? Color(white: 0.18)
                              : Color.white)
                )
        }
    }

    @ViewBuilder
    private func sectionWithFooter<Content: View>(
        header: String, footer: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section(header: header, content: content)
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func row<L: View, T: View>(@ViewBuilder _ label: () -> L,
                                       @ViewBuilder trailing: () -> T) -> some View {
        HStack {
            label()
            Spacer()
            trailing()
        }
        .padding(.vertical, 8)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.18))
            .frame(height: 1)
    }

    private func toggle(on: Bool) -> some View {
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(on ? Color.green : Color.gray.opacity(0.35))
                .frame(width: 34, height: 20)
            Circle()
                .fill(.white)
                .frame(width: 16, height: 16)
                .padding(2)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
        }
    }

    private func pillPicker(value: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(scheme == .dark
                      ? Color(white: 0.26)
                      : Color(white: 0.94))
        )
    }
}

private struct ScreenshotCopy {
    let headline: String
    let subline: String

    static let enterprise = ScreenshotCopy(
        headline: "Track Extra Usage\nin real time.",
        subline: "Live spend against your monthly cap, plan limits, and per-model breakdown — without leaving the keyboard."
    )
    static let pro = ScreenshotCopy(
        headline: "Never hit your\nweekly cap by surprise.",
        subline: "5-hour and weekly utilization at a glance, with per-model spend in API-equivalent USD."
    )
}

/// Full canvas: background → faux menu bar strip → headline / dropdown row.
private struct ScreenshotLayout<Dropdown: View>: View {
    let scheme: ColorScheme
    let menuBarText: String
    let copy: ScreenshotCopy
    @ViewBuilder var dropdown: () -> Dropdown

    var body: some View {
        ZStack(alignment: .topLeading) {
            canvasBackground
            VStack(alignment: .leading, spacing: 0) {
                menuBarStrip
                bodyRow
            }
        }
    }

    @ViewBuilder
    private var canvasBackground: some View {
        if scheme == .dark {
            LinearGradient(
                colors: [Color(red: 0.04, green: 0.04, blue: 0.07),
                         Color(red: 0.18, green: 0.10, blue: 0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.96, blue: 0.93),
                         Color(red: 1.00, green: 0.88, blue: 0.74)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }

    private var menuBarStrip: some View {
        HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "asterisk")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12, weight: .semibold))
                if !menuBarText.isEmpty {
                    Text(menuBarText)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(menuBarForeground)
                }
            }
            .padding(.horizontal, 10)
            Text("Thu 14:45")
                .font(.system(size: 12))
                .foregroundStyle(menuBarForeground)
                .padding(.trailing, 14)
        }
        .frame(height: 26)
        .background(
            scheme == .dark
                ? Color.black.opacity(0.55)
                : Color.white.opacity(0.85)
        )
    }

    private var menuBarForeground: Color {
        scheme == .dark ? Color.white.opacity(0.85) : Color.black.opacity(0.78)
    }

    private var bodyRow: some View {
        HStack(alignment: .top, spacing: 56) {
            headlineColumn
            dropdownColumn
            Spacer(minLength: 0)
        }
        .padding(.leading, 72)
        .padding(.trailing, 56)
        .padding(.top, 96)
    }

    private var headlineColumn: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(copy.headline)
                .font(.system(size: 56, weight: .bold, design: .default))
                .lineSpacing(-4)
                .foregroundStyle(scheme == .dark ? .white : .black)
            Text(copy.subline)
                .font(.system(size: 19))
                .foregroundStyle(scheme == .dark
                                 ? Color.white.opacity(0.72)
                                 : Color.black.opacity(0.66))
                .lineSpacing(2)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .frame(maxWidth: 460, alignment: .leading)
        .padding(.top, 36)
    }

    private var dropdownColumn: some View {
        dropdown()
            .frame(width: 340)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(scheme == .dark
                          ? Color(white: 0.16)
                          : Color(white: 0.995))
                    .shadow(color: .black.opacity(0.28), radius: 26, x: 0, y: 14)
            )
    }
}
