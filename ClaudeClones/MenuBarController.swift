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

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(manager: CloneManager, locator: InstanceLocating, router: LinkDelivering) {
        self.manager = manager
        self.locator = locator
        self.router = router
        self.model = CloneListModel(manager: manager, locator: locator)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleDeepLink(_:withReply:)),
            forEventClass: AppleEventLinkRouter.getURL,
            andEventID: AEEventID(AppleEventLinkRouter.getURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = StatusIcon.make()
        item.button?.target = self
        item.button?.action = #selector(togglePopover)

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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Deep links

    @objc private func handleDeepLink(_ event: NSAppleEventDescriptor,
                                      withReply reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AppleEventLinkRouter.directObject)?
                .stringValue,
              let url = URL(string: string) else { return }

        let clones = manager.clones()
        let running = Set(clones.filter { locator.runningPID(for: $0) != nil }.map(\.id))
        // Suggest the frontmost instance: almost always the window that started the
        // login or connector flow the link is completing.
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let suggested = clones.first { locator.runningPID(for: $0) == front }

        chooser.ask(link: string, clones: clones, running: running, suggested: suggested) { choice in
            guard let choice else { return }
            let result = choice.clone.map { self.router.deliver(url, to: $0) }
                ?? self.router.deliverToDefaultProfile(url, excluding: clones)
            if case .failed(let reason) = result { self.model.failure = reason }
        }
    }
}
