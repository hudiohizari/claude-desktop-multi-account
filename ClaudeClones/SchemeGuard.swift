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

    /// Watch for Claude starting up, then re-claim. The delay lets Claude finish its
    /// own registration first, otherwise it would just win the race again.
    func startWatching(bundleID: String = claudeBundleID, delay: TimeInterval = 3) {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            guard app?.bundleIdentifier == bundleID else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self?.reassertIfNeeded()
            }
        }
        Task { await reassertIfNeeded() }   // also fix drift from before we started
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
