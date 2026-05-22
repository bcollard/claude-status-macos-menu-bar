#!/usr/bin/env swift
// Renders Resources/AppIcon.icns from a programmatically-drawn template.
// Run from project root: swift scripts/make_icon.swift
import AppKit
import CoreText

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let projectRoot = FileManager.default.currentDirectoryPath
let work = (projectRoot as NSString).appendingPathComponent(".build/AppIcon.iconset")
let resources = (projectRoot as NSString).appendingPathComponent("Resources")
let outIcns = (resources as NSString).appendingPathComponent("AppIcon.icns")

try? FileManager.default.removeItem(atPath: work)
try FileManager.default.createDirectory(atPath: work, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: resources, withIntermediateDirectories: true)

func render(px: Int) -> Data {
    let size = NSSize(width: px, height: px)
    let img = NSImage(size: size)
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-square background with a warm gradient (Claude-ish orange→amber).
    let corner = CGFloat(px) * 0.225
    let rect = CGRect(x: 0, y: 0, width: px, height: px)
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
    ctx.saveGState()
    path.addClip()

    let colors = [
        NSColor(calibratedRed: 0.96, green: 0.49, blue: 0.20, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.85, green: 0.27, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: CGFloat(px)),
                           end: CGPoint(x: CGFloat(px), y: 0),
                           options: [])
    ctx.restoreGState()

    // Foreground glyph: a stylized starburst / sparkle.
    let cx = CGFloat(px) / 2
    let cy = CGFloat(px) / 2
    let R = CGFloat(px) * 0.32
    let r = CGFloat(px) * 0.10
    let star = NSBezierPath()
    let points = 8
    for i in 0..<points * 2 {
        let theta = (CGFloat(i) * .pi) / CGFloat(points) - .pi / 2
        let radius = (i % 2 == 0) ? R : r
        let x = cx + cos(theta) * radius
        let y = cy + sin(theta) * radius
        if i == 0 { star.move(to: NSPoint(x: x, y: y)) }
        else { star.line(to: NSPoint(x: x, y: y)) }
    }
    star.close()
    NSColor.white.withAlphaComponent(0.96).setFill()
    star.fill()

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    return png
}

for (name, px) in sizes {
    let png = render(px: px)
    let path = (work as NSString).appendingPathComponent(name)
    try png.write(to: URL(fileURLWithPath: path))
    print("→ \(name)  \(px)x\(px)")
}

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments = ["-c", "icns", "-o", outIcns, work]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else { fatalError("iconutil failed") }
print("✓ Wrote \(outIcns)")
