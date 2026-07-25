import AppKit

/// Creates, moves and removes the .app wrapper that launches Claude on one profile.
protocol CloneProvisioning {
    func provision(_ clone: Clone) throws
    func move(_ clone: Clone, to newPath: String) throws
    func remove(_ clone: Clone, includingProfile: Bool)
}

struct AppWrapperBuilder: CloneProvisioning {
    var icons = IconBadger()
    var launchServices = BundleRegistrar()

    func provision(_ clone: Clone) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: clone.appPath + "/Contents/MacOS",
                               withIntermediateDirectories: true)
        try fm.createDirectory(atPath: clone.profileDir, withIntermediateDirectories: true)

        try infoPlist(clone).write(toFile: clone.appPath + "/Contents/Info.plist",
                                   atomically: true, encoding: .utf8)
        let runner = clone.appPath + "/Contents/MacOS/run"
        try runScript(clone).write(toFile: runner, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runner)

        icons.badge(clone)
        launchServices.register(clone.appPath)
    }

    func move(_ clone: Clone, to newPath: String) throws {
        launchServices.unregister(clone.appPath)
        try? FileManager.default.removeItem(atPath: newPath)
        try FileManager.default.moveItem(atPath: clone.appPath, toPath: newPath)
    }

    func remove(_ clone: Clone, includingProfile: Bool) {
        launchServices.unregister(clone.appPath)
        try? FileManager.default.removeItem(atPath: clone.appPath)
        if includingProfile { try? FileManager.default.removeItem(atPath: clone.profileDir) }
    }

    // Two keys here are load-bearing:
    //
    // No LSEnvironment. macOS 26 refuses to launch a bundle that declares one
    // (_LSOpenURLsWithCompletionHandler error -54, before the executable runs), so
    // the profile is exported inside the script instead.
    //
    // LSArchitecturePriority arm64. The executable is a shell script, so
    // LaunchServices finds no Mach-O header to read an architecture from and starts
    // the app as x86_64; `exec` then inherits that, and Claude runs translated under
    // Rosetta, which renders a blank window and stalls the main process for seconds
    // at a time. On an Intel Mac this key is simply ignored.
    private func infoPlist(_ clone: Clone) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>CFBundleExecutable</key><string>run</string>
          <key>CFBundleIdentifier</key><string>\(clone.bundleID)</string>
          <key>CFBundleName</key><string>\(clone.displayName)</string>
          <key>CFBundleDisplayName</key><string>\(clone.displayName)</string>
          <key>CFBundlePackageType</key><string>APPL</string>
          <key>CFBundleShortVersionString</key><string>1.0</string>
          <key>LSMinimumSystemVersion</key><string>12.0</string>
          <key>LSArchitecturePriority</key><array><string>arm64</string></array>
        </dict></plist>
        """
    }

    private func runScript(_ clone: Clone) -> String {
        """
        #!/bin/bash
        export CLAUDE_USER_DATA_DIR="\(clone.profileDir)"
        pidfile="$CLAUDE_USER_DATA_DIR/.instance.pid"

        # Already running: focus it. Two processes on one profile leave the second
        # signed out, so never launch a second one.
        if [ -f "$pidfile" ]; then
          pid=$(cat "$pidfile")
          if ps -p "$pid" -o command= 2>/dev/null | grep -q 'Claude.app/Contents/MacOS/Claude'; then
            osascript -e "tell application \\"System Events\\" to set frontmost of \
        (first process whose unix id is $pid) to true" >/dev/null 2>&1
            exit 0
          fi
        fi

        mkdir -p "$CLAUDE_USER_DATA_DIR"
        echo $$ > "$pidfile"
        exec \(Paths.claudeBinary) "$@"

        """
    }
}

/// Claude ships its icon in Assets.car, so there is no .icns to copy - render the
/// live icon and badge it with the clone number.
struct IconBadger {
    func badge(_ clone: Clone) {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        NSWorkspace.shared.icon(forFile: Paths.claudeApp)
            .draw(in: NSRect(origin: .zero, size: size))

        let diameter: CGFloat = 200
        let circle = NSRect(x: size.width - diameter - 12, y: 12, width: diameter, height: diameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: circle).fill()
        NSColor.black.withAlphaComponent(0.85).setStroke()
        let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 4, dy: 4))
        ring.lineWidth = 8
        ring.stroke()

        let label = clone.badgeText as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.58, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        let textSize = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: circle.midX - textSize.width / 2,
                               y: circle.midY - textSize.height / 2),
                   withAttributes: attributes)
        image.unlockFocus()

        NSWorkspace.shared.setIcon(image, forFile: clone.appPath, options: [])
    }
}

struct BundleRegistrar {
    func register(_ path: String) { run(["-f", path]) }
    func unregister(_ path: String) { run(["-u", path]) }

    private func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Paths.lsregister)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
