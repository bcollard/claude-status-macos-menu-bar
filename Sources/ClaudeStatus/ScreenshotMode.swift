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
        switch plan {
        case "enterprise": store = DemoData.enterpriseStore()
        case "pro":        store = DemoData.proStore()
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

            let content = ZStack {
                canvasBackground(scheme)
                DropdownFrame(scheme: scheme) {
                    MenuView(store: store, screenshotMode: true)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .environment(\.colorScheme, scheme)

            let renderer = ImageRenderer(content: content)
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

    @ViewBuilder
    private static func canvasBackground(_ scheme: ColorScheme) -> some View {
        if scheme == .dark {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.09),
                         Color(red: 0.14, green: 0.10, blue: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.97, blue: 0.94),
                         Color(red: 1.00, green: 0.93, blue: 0.86)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

/// Popover-style background around the MenuView content.
private struct DropdownFrame<Content: View>: View {
    let scheme: ColorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(width: 340)
            .padding(0)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(scheme == .dark
                          ? Color(white: 0.16)
                          : Color(white: 0.99))
                    .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 10)
            )
    }
}
