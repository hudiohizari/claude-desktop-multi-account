import AppKit

/// The menu bar UI. Talks only to the protocols, never to LaunchServices or
/// Apple Events directly.
final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let manager: CloneManager
    private let locator: InstanceLocating
    private let router: LinkDelivering
    private let scheme = SchemeOwnership()
    private let prompt = Prompt()

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var shown: [Clone] = []

    init(manager: CloneManager, locator: InstanceLocating, router: LinkDelivering) {
        self.manager = manager
        self.locator = locator
        self.router = router
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleDeepLink(_:withReply:)),
            forEventClass: AppleEventLinkRouter.getURL,
            andEventID: AEEventID(AppleEventLinkRouter.getURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = NSImage(systemSymbolName: "square.stack.3d.up",
                                     accessibilityDescription: "Claude Clones")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        shown = manager.clones()

        if shown.isEmpty {
            let empty = NSMenuItem(title: "No clones yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, clone) in shown.enumerated() {
            let running = locator.runningPID(for: clone) != nil
            let entry = menuItem((running ? "● " : "○ ") + clone.displayName,
                                 #selector(openClone(_:)), tag: index)
            let submenu = NSMenu()
            submenu.addItem(menuItem("Rename…", #selector(renameClone(_:)), tag: index))
            submenu.addItem(menuItem("Reveal Profile", #selector(revealProfile(_:)), tag: index))
            submenu.addItem(menuItem("Delete…", #selector(deleteClone(_:)), tag: index))
            entry.submenu = submenu
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("New Clone…", #selector(newClone)))
        menu.addItem(.separator())

        let owned = scheme.ownedByUs
        let status = NSMenuItem(title: "Links open in: " + (owned ? "this app (you choose)" : "Claude"),
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(menuItem(owned ? "Give claude:// back to Claude" : "Route claude:// links here",
                              #selector(toggleSchemeOwner)))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func menuItem(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.tag = tag
        return entry
    }

    // MARK: - Clone actions

    @objc private func openClone(_ sender: NSMenuItem) {
        let clone = shown[sender.tag]
        if let pid = locator.runningPID(for: clone) {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: clone.appPath),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func newClone() {
        let next = (manager.clones().map(\.id).max() ?? 0) + 1
        guard let name = prompt.text(title: "New Clone",
                                     message: "Name for this profile. It becomes \"Claude <name>.app\".",
                                     value: "Clone \(next)") else { return }
        do { try manager.create(name: name) }
        catch { prompt.report("Could not create the clone", error.localizedDescription) }
    }

    @objc private func renameClone(_ sender: NSMenuItem) {
        let clone = shown[sender.tag]
        guard let name = prompt.text(title: "Rename",
                                     message: "New name for \(clone.displayName).",
                                     value: clone.name), name != clone.name else { return }
        do { try manager.rename(clone, to: name) }
        catch { prompt.report("Could not rename", error.localizedDescription) }
    }

    @objc private func revealProfile(_ sender: NSMenuItem) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: shown[sender.tag].profileDir)
    }

    @objc private func deleteClone(_ sender: NSMenuItem) {
        let clone = shown[sender.tag]
        guard let alsoProfile = prompt.deleteChoice(for: clone) else { return }
        manager.delete(clone, includingProfile: alsoProfile)
    }

    @objc private func toggleSchemeOwner() {
        let claim = !scheme.ownedByUs
        Task { @MainActor in
            do { try await scheme.setOwner(toUs: claim) }
            catch { prompt.report("Could not change the handler", error.localizedDescription) }
        }
    }

    // MARK: - Deep links

    @objc private func handleDeepLink(_ event: NSAppleEventDescriptor,
                                      withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AppleEventLinkRouter.directObject)?
                .stringValue,
              let url = URL(string: string) else { return }

        let clones = manager.clones()
        let running = clones.filter { locator.runningPID(for: $0) != nil }
        // Default to the frontmost instance — almost always the window that started
        // the login or connector flow.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let suggested = clones.firstIndex { locator.runningPID(for: $0) == front }

        guard let choice = prompt.target(for: string, clones: clones,
                                         running: running, suggested: suggested) else { return }

        let result: Delivery
        switch choice {
        case .defaultProfile: result = router.deliverToDefaultProfile(url, excluding: clones)
        case .clone(let index): result = router.deliver(url, to: clones[index])
        }
        if case .failed(let reason) = result { prompt.report("Could not open the link", reason) }
    }
}
