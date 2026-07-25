import AppKit

enum Delivery: Equatable {
    case sent(pid_t)      // handed to a running instance
    case launched         // clone was not running; started with the link
    case failed(String)
}

/// Hands a claude:// link to one chosen instance.
protocol LinkDelivering {
    func deliver(_ url: URL, to clone: Clone) -> Delivery
    func deliverToDefaultProfile(_ url: URL, excluding clones: [Clone]) -> Delivery
}

struct AppleEventLinkRouter: LinkDelivering {
    static let getURL = AEEventClass(0x4755_524C)   // 'GURL'
    static let directObject = AEKeyword(0x2D2D_2D2D)  // '----'

    let locator: InstanceLocating

    func deliver(_ url: URL, to clone: Clone) -> Delivery {
        guard let pid = locator.runningPID(for: clone) else {
            launch(URL(fileURLWithPath: clone.appPath), with: url)
            return .launched
        }
        return send(url.absoluteString, to: pid)
            ? .sent(pid)
            : .failed("macOS may be waiting for permission to control \(clone.displayName). "
                      + "Check System Settings › Privacy & Security › Automation.")
    }

    func deliverToDefaultProfile(_ url: URL, excluding clones: [Clone]) -> Delivery {
        guard let pid = locator.defaultProfilePID(excluding: clones) else {
            launch(URL(fileURLWithPath: Paths.claudeApp), with: url)
            return .launched
        }
        return send(url.absoluteString, to: pid) ? .sent(pid) : .failed("Claude did not accept the link.")
    }

    /// Deliver by pid rather than bundle: every instance shares one bundle id, so
    /// LaunchServices would always pick the first-launched one.
    private func send(_ url: String, to pid: pid_t) -> Bool {
        let event = NSAppleEventDescriptor(
            eventClass: Self.getURL,
            eventID: AEEventID(Self.getURL),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(-1),        // kAutoGenerateReturnID
            transactionID: AETransactionID(0))
        event.setParam(NSAppleEventDescriptor(string: url), forKeyword: Self.directObject)
        return (try? event.sendEvent(options: [.noReply], timeout: 5)) != nil
    }

    private func launch(_ app: URL, with url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
    }
}

/// Who currently owns the claude:// scheme.
struct SchemeOwnership: SchemeOwning {
    let scheme = "claude"

    var ownerBundleID: String? {
        NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://x")!)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    var ownedByUs: Bool { ownerBundleID == Bundle.main.bundleIdentifier }

    func setOwner(toUs: Bool) async throws {
        let target = toUs ? Bundle.main.bundleURL : URL(fileURLWithPath: Paths.claudeApp)
        try await NSWorkspace.shared.setDefaultApplication(at: target, toOpenURLsWithScheme: scheme)
    }
}
