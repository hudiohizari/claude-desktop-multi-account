import AppKit

/// Every dialog the app shows, so the controller holds no NSAlert wiring.
struct Prompt {
    enum Target {
        case defaultProfile
        case clone(Int)
    }

    func text(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// nil = cancelled, false = launcher only, true = launcher and profile.
    func deleteChoice(for clone: Clone) -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Delete \(clone.displayName)?"
        alert.informativeText = "Removes the launcher. Its profile at \(clone.profileDir) holds "
            + "the login, chats and Cowork VM (\(DiskSize.of(clone.profileDir)))."
        alert.addButton(withTitle: "Delete Launcher Only")
        alert.addButton(withTitle: "Delete Launcher and Profile")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return false
        case .alertSecondButtonReturn: return true
        default: return nil
        }
    }

    func target(for link: String, clones: [Clone], running: [Clone], suggested: Int?) -> Target? {
        let alert = NSAlert()
        alert.messageText = "Open this link in which profile?"
        alert.informativeText = String(link.prefix(140))

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 25))
        picker.addItem(withTitle: "Claude (default profile)")
        for clone in clones {
            let isRunning = running.contains { $0.id == clone.id }
            picker.addItem(withTitle: clone.displayName + (isRunning ? " — running" : ""))
        }
        if let suggested { picker.selectItem(at: suggested + 1) }
        alert.accessoryView = picker
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = picker.indexOfSelectedItem
        return index == 0 ? .defaultProfile : .clone(index - 1)
    }

    func report(_ text: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum DiskSize {
    static func of(_ path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sh", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        return output?.split(separator: "\t").first.map(String.init) ?? "unknown size"
    }
}
