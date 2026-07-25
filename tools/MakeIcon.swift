import AppKit

// Draws the app icon and writes an .iconset for iconutil.
// Offscreen bitmap contexts only, so it works without a window server.

let outputDir = CommandLine.arguments.dropFirst().first ?? "build/AppIcon.iconset"

func draw(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let unit = size / 1024

    // Rounded tile with a slate gradient.
    let tile = canvas.insetBy(dx: 40 * unit, dy: 40 * unit)
    let tilePath = NSBezierPath(roundedRect: tile,
                                xRadius: 200 * unit, yRadius: 200 * unit)
    tilePath.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.24, green: 0.24, blue: 0.27, alpha: 1),
                        NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)])?
        .draw(in: tile, angle: -90)

    // Three stacked profile cards, back to front.
    let cards: [(offset: CGFloat, color: NSColor)] = [
        (150, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22)),
        (75, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.45)),
        (0, NSColor(srgbRed: 0.85, green: 0.46, blue: 0.34, alpha: 1)),
    ]
    for card in cards {
        let rect = NSRect(x: 270 * unit,
                          y: (250 + card.offset) * unit,
                          width: 484 * unit, height: 340 * unit)
        let path = NSBezierPath(roundedRect: rect, xRadius: 70 * unit, yRadius: 70 * unit)
        card.color.setFill()
        path.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
try? fm.removeItem(atPath: outputDir)
try! fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// iconutil expects these exact names.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    let png = draw(size: variant.size).representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "\(outputDir)/\(variant.name).png"))
}
print("wrote \(variants.count) sizes to \(outputDir)")
