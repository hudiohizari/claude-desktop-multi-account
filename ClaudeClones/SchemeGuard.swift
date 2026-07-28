import AppKit

/// Who owns the claude:// scheme. Behind a protocol so the guard's logic can be
/// tested without touching the real LaunchServices database.
protocol SchemeOwning {
    var ownedByUs: Bool { get }
    func setOwner(toUs: Bool) async throws
}

/// Keeps the claude:// scheme pointed here when the user asked for it.
///
/// Claude calls `setAsDefaultProtocolClient` every time it starts, so each launch of
/// Claude or of any clone silently takes the scheme back. Without this, routing stops
/// working on its own and the only clue is that links stop asking.
@MainActor
final class SchemeGuard {
    private let ownership: SchemeOwning
    private let defaults: UserDefaults
    private let key = "routeLinksHere"
    private var observer: NSObjectProtocol?
    private var poller: Timer?

    /// A launch is answered several times over: Claude registers itself somewhere in
    /// its startup, and how long that takes varies with machine and cold start, so a
    /// single delayed check loses the race whenever Claude is slower than expected.
    static let reclaimDelays: [TimeInterval] = [2, 6, 12, 25]

    /// Backstop for anything the launch notification misses.
    static let pollInterval: TimeInterval = 30

    init(ownership: SchemeOwning, defaults: UserDefaults = .standard) {
        self.ownership = ownership
        self.defaults = defaults
    }

    /// What the user asked for, which is not the same as who currently owns the
    /// scheme; the gap between the two is exactly what this class closes.
    var wantsOwnership: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key) }
    }

    var ownedByUs: Bool { ownership.ownedByUs }

    func setWanted(_ wanted: Bool) async throws {
        wantsOwnership = wanted
        try await ownership.setOwner(toUs: wanted)
    }

    /// Re-assert ownership if the user wants it and something took it away.
    /// Returns true when a re-claim was actually needed.
    @discardableResult
    func reassertIfNeeded() async -> Bool {
        guard wantsOwnership, !ownership.ownedByUs else { return false }
        do {
            try await ownership.setOwner(toUs: true)
            Log.write("scheme: reclaimed claude:// after another app took it")
            return true
        } catch {
            Log.write("scheme: reclaim failed, \(error.localizedDescription)")
            return false
        }
    }

    /// Any process running the Claude binary counts, whatever bundle launched it.
    /// Matching on bundle id alone missed clones, whose wrapper bundle registers
    /// under its own id while running the same executable.
    static func isClaude(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == claudeBundleID
            || app.executableURL?.path == Paths.claudeBinary
    }

    func startWatching() {
        guard observer == nil else { return }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  Self.isClaude(app) else { return }
            Task { @MainActor [weak self] in await self?.reclaimRepeatedly() }
        }

        // Cheap enough to run forever: one LaunchServices lookup, and only when the
        // user actually wants the scheme.
        poller = Timer.scheduledTimer(withTimeInterval: Self.pollInterval,
                                      repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reassertIfNeeded() }
        }

        Task { await reassertIfNeeded() }   // fix drift from before we started
    }

    /// Claude can register at any point during its startup, and can register more
    /// than once, so answer a launch with several attempts rather than one.
    private func reclaimRepeatedly() async {
        for delay in Self.reclaimDelays {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await reassertIfNeeded()
        }
    }

    deinit {
        poller?.invalidate()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
