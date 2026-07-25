import AppKit

// Composition root: the only place that knows which implementations are used.

let manager = CloneManager(store: JSONCloneStore(), builder: AppWrapperBuilder())
let locator = PidFileInstanceLocator()

let arguments = Array(CommandLine.arguments.dropFirst())
if let first = arguments.first, first.hasPrefix("--") {
    exit(CLI(manager: manager, locator: locator).run(arguments))
}

MainActor.assumeIsolated {
    let controller = MenuBarController(manager: manager,
                                       locator: locator,
                                       router: AppleEventLinkRouter(locator: locator))
    let app = NSApplication.shared
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
