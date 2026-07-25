import AppKit
import SwiftUI

/// Owns the status item, its popover, and the deep-link chooser. Talks only to
/// the model and the protocols - never to LaunchServices or Apple Events itself.
@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model: CloneListModel
    private let manager: CloneManager
    private let locator: InstanceLocating
    private let router: LinkDelivering
    private let chooser = LinkChooser()
    private let guardian: SchemeGuard

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(manager: CloneManager, locator: InstanceLocating, router: LinkDelivering) {
        self.manager = manager
        self.locator = locator
        self.router = router
        let guardian = SchemeGuard(ownership: SchemeOwnership())
        self.guardian = guardian
        self.model = CloneListModel(manager: manager, locator: locator, guardian: guardian)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = StatusIcon.make()
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

        guardian.startWatching()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            model.recheckSchemeOwnership()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Deep links

    /// The only way this app should receive links. Do NOT also install a GURL
    /// handler through NSAppleEventManager: that replaces AppKit's handler, which is
    /// the one that acknowledges the event, and without the acknowledgement macOS
    /// treats the link as unhandled and passes it on to the next app registered for
    /// claude://, so Claude opens it too.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "claude" {
            Log.write("route: received \(Redact.link(url))")
            route(url)
        }
    }

    private func route(_ url: URL) {
        let clones = manager.clones()
        let running = Set(clones.filter { locator.runningPID(for: $0) != nil }.map(\.id))
        // Suggest the frontmost instance: almost always the window that started the
        // login or connector flow the link is completing.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let suggested = clones.first { locator.runningPID(for: $0) == front }

        chooser.ask(link: url.absoluteString, clones: clones,
                    running: running, suggested: suggested) { choice in
            guard let choice else { return }
            let result = choice.clone.map { self.router.deliver(url, to: $0) }
                ?? self.router.deliverToDefaultProfile(url, excluding: clones)
            if case .failed(let reason) = result { self.model.failure = reason }
        }
    }
}
