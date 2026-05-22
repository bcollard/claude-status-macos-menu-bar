import SwiftUI
import AppKit

@MainActor
enum ScreenshotMode {
    /// App Store accepts 2880×1800 / 2560×1600 / 1440×900 / 1280×800 for
    /// Mac apps. We target 2880×1800 (= 1440×900 logical at 2x).
    static let canvasWidth: CGFloat = 1440
    static let canvasHeight: CGFloat = 900

    /// Render the MenuView dropdown to PNG with anonymous demo data.
    /// Invoked via `ClaudeStatus --screenshot <plan> [outDir]` from CLI.
    static func run(plan rawPlan: String, outDir: String) -> Never {
        let plan = rawPlan.lowercased()
        let store: UsageStore
        let copy: ScreenshotCopy
        switch plan {
        case "enterprise":
            store = DemoData.enterpriseStore()
            copy = .enterprise
        case "pro":
            store = DemoData.proStore()
            copy = .pro
        default:
            FileHandle.standardError.write(Data("unknown plan: \(rawPlan) (expected 'enterprise' or 'pro')\n".utf8))
            exit(2)
        }

        let fm = FileManager.default
        try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        for scheme: ColorScheme in [.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            let outURL = URL(fileURLWithPath: outDir)
                .appendingPathComponent("claude-status-\(plan)-\(name).png")

            let layout = ScreenshotLayout(
                scheme: scheme,
                menuBarText: store.menuBarCount ?? "",
                copy: copy
            ) {
                MenuView(store: store, screenshotMode: true)
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: layout)
            renderer.scale = 2.0
            renderer.isOpaque = true

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

        exit(0)
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
