#!/usr/bin/env swift

// Generates 5 MTG Keyan app icons — one per WUBRG mana color — as glossy
// 3D orbs on a dark cosmic gradient background. Each orb features the
// canonical Wizards mana symbol in white, rendered via SF Symbols
// (sun.max / drop / skull / flame / tree).
//
// Output:
//   Resources/Assets.xcassets/AppIcon.appiconset/MTGKeyanAppIcon_1024.png  (W primary)
//   Resources/AppIcons/AppIcon-U.png, AppIcon-U@2x.png, AppIcon-U@3x.png   (Blue alt)
//   Resources/AppIcons/AppIcon-B.png, AppIcon-B@2x.png, AppIcon-B@3x.png   (Black alt)
//   Resources/AppIcons/AppIcon-R.png, AppIcon-R@2x.png, AppIcon-R@3x.png   (Red alt)
//   Resources/AppIcons/AppIcon-G.png, AppIcon-G@2x.png, AppIcon-G@3x.png   (Green alt)
//
// Run with:
//   swift scripts/generate_icon.swift

import Foundation
import CoreGraphics
import AppKit

// MARK: - Color helpers

extension CGColor {
    func darker(by amount: CGFloat) -> CGColor {
        guard let c = components, c.count >= 3 else { return self }
        return CGColor(
            red: max(0, c[0] - amount),
            green: max(0, c[1] - amount),
            blue: max(0, c[2] - amount),
            alpha: c.count > 3 ? c[3] : 1
        )
    }
    func lighter(by amount: CGFloat) -> CGColor {
        guard let c = components, c.count >= 3 else { return self }
        return CGColor(
            red: min(1, c[0] + amount),
            green: min(1, c[1] + amount),
            blue: min(1, c[2] + amount),
            alpha: c.count > 3 ? c[3] : 1
        )
    }
}

// MARK: - Icon definitions

struct ManaIcon {
    let key: String          // W / U / B / R / G
    let orbColor: CGColor    // bright base color of the orb
    let symbolName: String   // SF Symbol name
}

let icons: [ManaIcon] = [
    ManaIcon(
        key: "W",
        orbColor: CGColor(red: 0.984, green: 0.929, blue: 0.722, alpha: 1),  // warm cream
        symbolName: "sun.max.fill"
    ),
    ManaIcon(
        key: "U",
        orbColor: CGColor(red: 0.298, green: 0.643, blue: 0.918, alpha: 1),  // sky blue
        symbolName: "drop.fill"
    ),
    ManaIcon(
        key: "B",
        orbColor: CGColor(red: 0.357, green: 0.298, blue: 0.388, alpha: 1),  // dusk purple
        symbolName: "moon.fill"
    ),
    ManaIcon(
        key: "R",
        orbColor: CGColor(red: 0.929, green: 0.310, blue: 0.231, alpha: 1),  // vivid red
        symbolName: "flame.fill"
    ),
    ManaIcon(
        key: "G",
        orbColor: CGColor(red: 0.388, green: 0.745, blue: 0.420, alpha: 1),  // leaf green
        symbolName: "tree.fill"
    ),
]

// Cosmic background — same for all icons so the family feels coherent
let bgInner = CGColor(red: 0.094, green: 0.078, blue: 0.184, alpha: 1)  // deep indigo
let bgOuter = CGColor(red: 0.020, green: 0.012, blue: 0.043, alpha: 1)  // near-black

// MARK: - Tinted SF Symbol drawing

/// Renders an SF Symbol into the given CG context with the requested
/// tint color. Uses an offscreen bitmap + destination-in compositing
/// to colorize the symbol's alpha channel.
func drawTintedSymbol(
    name: String,
    rect: CGRect,
    color: NSColor,
    in ctx: CGContext
) {
    let pointSize = max(8, rect.height * 0.95)
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .heavy)
    guard let baseImage = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let configured = baseImage.withSymbolConfiguration(config) else {
        print("WARN: SF Symbol '\(name)' unavailable, skipping")
        return
    }

    let pixelW = max(1, Int(rect.width.rounded()))
    let pixelH = max(1, Int(rect.height.rounded()))

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelW,
        pixelsHigh: pixelH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        print("WARN: failed to create offscreen bitmap")
        return
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // Fill with the tint color
    color.set()
    NSRect(x: 0, y: 0, width: CGFloat(pixelW), height: CGFloat(pixelH)).fill()

    // Mask by the symbol's alpha
    let imgSize = configured.size
    let scale = min(CGFloat(pixelW) / imgSize.width, CGFloat(pixelH) / imgSize.height)
    let drawW = imgSize.width * scale
    let drawH = imgSize.height * scale
    let drawRect = NSRect(
        x: (CGFloat(pixelW) - drawW) / 2,
        y: (CGFloat(pixelH) - drawH) / 2,
        width: drawW,
        height: drawH
    )
    configured.draw(
        in: drawRect,
        from: .zero,
        operation: .destinationIn,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    if let cgImage = bitmap.cgImage {
        ctx.draw(cgImage, in: rect)
    }
}

// MARK: - Orb rendering

/// Draws a glossy 3D orb at the given location: drop shadow, sphere
/// shading via vertical gradient, specular highlight in the upper-left,
/// and a thin rim light at the top.
func drawOrb(
    in ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    color: CGColor,
    colorSpace: CGColorSpace
) {
    let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )

    // 1. Drop shadow underneath
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -radius * 0.10),
        blur: radius * 0.32,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.65)
    )
    ctx.setFillColor(color)
    ctx.fillEllipse(in: rect)
    ctx.restoreGState()

    // 2. Vertical sphere-shading gradient (lighter top, darker bottom)
    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()
    let lighter = color.lighter(by: 0.15)
    let darker = color.darker(by: 0.35)
    let sphereGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [lighter, color, darker] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    // Note: CG default is y-down. "Top" of the orb in image coords is y - radius (smaller y).
    ctx.drawLinearGradient(
        sphereGradient,
        start: CGPoint(x: center.x, y: center.y - radius),
        end: CGPoint(x: center.x, y: center.y + radius),
        options: []
    )
    ctx.restoreGState()
}

/// Draws the upper-left specular highlight on top of the orb (and any
/// symbol that's already been composited inside it). Drawn last so it
/// shines through the symbol too — like real glass.
func drawOrbHighlight(
    in ctx: CGContext,
    center: CGPoint,
    radius: CGFloat,
    colorSpace: CGColorSpace
) {
    let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )

    // 1. Soft white blob in the upper-left of the orb
    ctx.saveGState()
    ctx.addEllipse(in: rect)
    ctx.clip()
    let highlightCenter = CGPoint(
        x: center.x - radius * 0.35,
        y: center.y - radius * 0.40
    )
    let highlightGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.55),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        highlightGradient,
        startCenter: highlightCenter,
        startRadius: 0,
        endCenter: highlightCenter,
        endRadius: radius * 0.65,
        options: []
    )
    ctx.restoreGState()

    // 2. Thin top rim light
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.40))
    ctx.setLineWidth(radius * 0.025)
    ctx.beginPath()
    // Arc across the upper portion of the orb
    ctx.addArc(
        center: center,
        radius: radius - radius * 0.025,
        startAngle: -2.7,
        endAngle: -0.5,
        clockwise: false
    )
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Render single icon at given size

func renderIcon(_ icon: ManaIcon, size: CGFloat) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: Int(size),
        height: Int(size),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    let center = CGPoint(x: size / 2, y: size / 2)

    // 1. Cosmic background — radial gradient
    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [bgInner, bgOuter] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        bgGradient,
        startCenter: CGPoint(x: size * 0.40, y: size * 0.35),
        startRadius: 0,
        endCenter: center,
        endRadius: size * 0.80,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // 2. Sprinkle a few faint star points
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.65))
    let starPositions: [(CGFloat, CGFloat, CGFloat)] = [
        (0.12, 0.18, 0.004),
        (0.85, 0.22, 0.005),
        (0.78, 0.78, 0.003),
        (0.18, 0.82, 0.0035),
        (0.92, 0.55, 0.0025),
        (0.08, 0.55, 0.003),
        (0.55, 0.10, 0.0025),
        (0.30, 0.92, 0.003),
    ]
    for (xPct, yPct, rPct) in starPositions {
        let r = size * rPct
        ctx.fillEllipse(in: CGRect(
            x: size * xPct - r,
            y: size * yPct - r,
            width: r * 2,
            height: r * 2
        ))
    }
    ctx.restoreGState()

    // 3. The orb
    let orbRadius = size * 0.34
    drawOrb(in: ctx, center: center, radius: orbRadius, color: icon.orbColor, colorSpace: colorSpace)

    // 4. Mana symbol inside the orb (white)
    let symbolSize = orbRadius * 1.05
    let symbolRect = CGRect(
        x: center.x - symbolSize / 2,
        y: center.y - symbolSize / 2,
        width: symbolSize,
        height: symbolSize
    )
    // Symbol color: white-ish but slightly tinted with the orb hue for harmony
    let symbolColor = NSColor(white: 1.0, alpha: 0.95)
    drawTintedSymbol(name: icon.symbolName, rect: symbolRect, color: symbolColor, in: ctx)

    // 5. Highlight + rim light — drawn last so they overlay the symbol
    drawOrbHighlight(in: ctx, center: center, radius: orbRadius, colorSpace: colorSpace)

    // Convert to PNG
    guard let cgImage = ctx.makeImage() else { return nil }
    let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        return nil
    }
    return pngData
}

// MARK: - Output paths

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()

let primaryURL = projectRoot
    .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset/MTGKeyanAppIcon_1024.png")

let altIconsDir = projectRoot.appendingPathComponent("Resources/AppIcons")
try? FileManager.default.createDirectory(at: altIconsDir, withIntermediateDirectories: true)

// MARK: - Generate

print("Generating MTG Keyan icon set…")

// Primary: W at 1024×1024 → asset catalog
guard let wData = renderIcon(icons[0], size: 1024) else {
    print("ERROR: failed to render W primary at 1024")
    exit(1)
}
try wData.write(to: primaryURL)
print("✓ \(primaryURL.lastPathComponent) (\(wData.count) bytes)")

// Alternates: U / B / R / G at 60, 120, 180
let altSizes: [(size: CGFloat, suffix: String)] = [
    (60, ""),
    (120, "@2x"),
    (180, "@3x"),
]
for icon in icons.dropFirst() {  // U, B, R, G
    for (sz, suffix) in altSizes {
        guard let data = renderIcon(icon, size: sz) else {
            print("ERROR: failed to render \(icon.key) at \(sz)")
            continue
        }
        let filename = "AppIcon-\(icon.key)\(suffix).png"
        let url = altIconsDir.appendingPathComponent(filename)
        try data.write(to: url)
        print("✓ \(filename) (\(data.count) bytes)")
    }
}

// Also generate a 1024 preview of each color so the user can inspect
// in the docs/icon folder
let previewDir = projectRoot.appendingPathComponent("docs/icon")
try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
for icon in icons {
    if let data = renderIcon(icon, size: 1024) {
        let url = previewDir.appendingPathComponent("preview-\(icon.key).png")
        try? data.write(to: url)
    }
}
print("✓ Previews in docs/icon/")

print("\nDone. Run ./scripts/deploy.sh to install on device.")
