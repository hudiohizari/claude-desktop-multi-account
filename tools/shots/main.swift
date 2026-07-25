import AppKit
import SwiftUI

// Renders the real SwiftUI views to PNGs for the README, using stub
// implementations of the app's protocols and a store in a temp directory, so no
// clone is created and nothing on the machine is touched.

let outputDir = CommandLine.arguments.dropFirst().first ?? "docs/screenshots"

struct StubProvisioner: CloneProvisioning {
    func provision(_ clone: Clone) throws {}
    func move(_ clone: Clone, to newPath: String) throws {}
    func remove(_ clone: Clone, includingProfile: Bool) {}
}

struct StubLocator: InstanceLocating {
    let running: Set<Int>
    func runningPID(for clone: Clone) -> pid_t? { running.contains(clone.id) ? 4242 : nil }
    func defaultProfilePID(excluding clones: [Clone]) -> pid_t? { 1 }
}

/// Captured through a real offscreen window, not ImageRenderer: that one renders
/// ScrollView content blank and draws AppKit-backed controls, like the switch, as
/// placeholder boxes.
@MainActor
func capture<V: View>(_ view: V, backdrop: NSColor) -> NSBitmapImageRep? {
    let controller = NSHostingController(rootView: view)
    let window = NSWindow(contentViewController: controller)
    window.styleMask = [.borderless]
    window.backgroundColor = backdrop
    window.appearance = NSAppearance(named: .darkAqua)
    window.setContentSize(controller.view.fittingSize)
    window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))   // keep it off any display
    window.makeKeyAndOrderFront(nil)   // key, so prominent buttons draw tinted

    // Let SwiftUI lay out and the material blur settle before capturing.
    RunLoop.current.run(until: Date().addingTimeInterval(0.6))

    guard let content = window.contentView,
          let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
    else { return nil }
    content.cacheDisplay(in: content.bounds, to: rep)
    window.orderOut(nil)
    return rep
}

func write(_ image: NSImage, to name: String) {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        print("failed to encode \(name)")
        return
    }
    let path = "\(outputDir)/\(name).png"
    try? png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) (\(bitmap.pixelsWide)x\(bitmap.pixelsHigh) px)")
}

/// One panel on a padded backdrop, so the shot reads as a floating window.
@MainActor
func render<V: View>(_ view: V, to name: String, backdrop: NSColor) {
    guard let rep = capture(view, backdrop: backdrop) else {
        print("failed to render \(name)")
        return
    }
    let inset: CGFloat = 24
    let size = NSSize(width: rep.size.width + inset * 2, height: rep.size.height + inset * 2)
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    backdrop.setFill()
    NSRect(origin: .zero, size: size).fill()
    rep.draw(in: NSRect(x: inset, y: inset, width: rep.size.width, height: rep.size.height))
    canvas.unlockFocus()
    write(canvas, to: name)
}

/// 1280x640 card for GitHub's social preview, which becomes the link card wherever
/// the repo gets shared.
@MainActor
func renderSocialPreview<V: View>(_ view: V, backdrop: NSColor) {
    guard let panel = capture(view, backdrop: backdrop) else { return }

    let size = NSSize(width: 1280, height: 640)
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    NSColor(white: 0.06, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()

    let title = "Claude Clones" as NSString
    let subtitle = "Run multiple Claude Desktop accounts side by side on macOS, "
        + "each with its own login, MCP servers and Cowork VM." as NSString
    let accent = NSColor(srgbRed: 0.85, green: 0.46, blue: 0.34, alpha: 1)

    title.draw(at: NSPoint(x: 80, y: 400), withAttributes: [
        .font: NSFont.systemFont(ofSize: 58, weight: .bold),
        .foregroundColor: NSColor.white,
    ])
    subtitle.draw(in: NSRect(x: 80, y: 200, width: 620, height: 170), withAttributes: [
        .font: NSFont.systemFont(ofSize: 21, weight: .regular),
        .foregroundColor: NSColor(white: 0.72, alpha: 1),
    ])
    ("claude:// link routing  ·  no re-signed copies  ·  MIT" as NSString)
        .draw(at: NSPoint(x: 80, y: 150), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: accent,
        ])

    // Panel on the right, scaled to fit with a margin.
    let maxHeight = size.height - 120
    let scale = min(1, maxHeight / panel.size.height)
    let panelSize = NSSize(width: panel.size.width * scale, height: panel.size.height * scale)
    panel.draw(in: NSRect(x: size.width - panelSize.width - 80,
                          y: (size.height - panelSize.height) / 2,
                          width: panelSize.width, height: panelSize.height))
    canvas.unlockFocus()
    write(canvas, to: "social-preview")
}

@MainActor
func main() {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

    let temp = fm.temporaryDirectory.appendingPathComponent("claudeclones-shots").path
    try? fm.removeItem(atPath: temp)
    try? fm.createDirectory(atPath: temp, withIntermediateDirectories: true)

    // Clones need an existing bundle path, otherwise CloneManager prunes them.
    let sample = [(1, "Work"), (2, "Personal"), (3, "Client A")].map { id, name -> Clone in
        let appPath = "\(temp)/Claude \(name).app"
        try? fm.createDirectory(atPath: appPath, withIntermediateDirectories: true)
        return Clone(id: id, name: name,
                     profileDir: "\(temp)/clone-\(id)", appPath: appPath)
    }

    let store = JSONCloneStore(file: "\(temp)/clones.json")
    store.save(sample)
    let locator = StubLocator(running: [1, 3])
    let manager = CloneManager(store: store, builder: StubProvisioner())

    let populated = CloneListModel(manager: manager, locator: locator)
    populated.refresh()
    render(PopoverView(model: populated), to: "popover",
           backdrop: NSColor(white: 0.07, alpha: 1))

    let empty = CloneListModel(manager: CloneManager(store: JSONCloneStore(file: "\(temp)/none.json"),
                                                     builder: StubProvisioner()),
                               locator: locator)
    empty.refresh()
    render(PopoverView(model: empty), to: "empty-state",
           backdrop: NSColor(white: 0.07, alpha: 1))

    render(LinkChooserView(link: "claude://claude.ai/magic-link?token=abc123",
                           clones: sample,
                           running: [1, 3],
                           selected: 1,
                           done: { _ in }),
           to: "chooser",
           backdrop: NSColor(white: 0.07, alpha: 1))

    renderSocialPreview(PopoverView(model: populated), backdrop: NSColor(white: 0.07, alpha: 1))

    try? fm.removeItem(atPath: temp)
}

NSApplication.shared.setActivationPolicy(.accessory)
MainActor.assumeIsolated { main() }
