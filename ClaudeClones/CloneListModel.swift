import AppKit
import SwiftUI

/// View state for the popover. Holds no AppKit or LaunchServices knowledge of its
/// own - it asks the same protocols the CLI uses.
@MainActor
final class CloneListModel: ObservableObject {
    struct Row: Identifiable {
        let clone: Clone
        let pid: pid_t?
        /// Running, yet its profile directory is still empty. Claude writes into a
        /// profile within seconds of starting, so an empty one means
        /// CLAUDE_USER_DATA_DIR was ignored and this instance is sharing the default
        /// profile: the one failure mode that silently mixes two accounts.
        let isolationSuspect: Bool
        var id: Int { clone.id }
        var isRunning: Bool { pid != nil }
    }

    @Published private(set) var rows: [Row] = []
    @Published var editing: Int?          // clone id being renamed inline
    @Published var pendingDelete: Clone?  // clone awaiting delete confirmation
    @Published var routesHere = false
    /// The stock instance on the default profile, if it is running.
    @Published private(set) var defaultPID: pid_t?
    @Published var failure: String?

    private let manager: CloneManager
    private let locator: InstanceLocating
    private let guardian: SchemeGuard

    init(manager: CloneManager,
         locator: InstanceLocating,
         guardian: SchemeGuard? = nil) {
        self.manager = manager
        self.locator = locator
        self.guardian = guardian ?? SchemeGuard(ownership: SchemeOwnership())
    }

    func refresh() {
        rows = manager.clones().map { clone in
            let pid = locator.runningPID(for: clone)
            return Row(clone: clone,
                       pid: pid,
                       isolationSuspect: pid != nil && Self.profileLooksUnused(clone))
        }
        defaultPID = locator.defaultProfilePID(excluding: rows.map(\.clone))
        // What the user asked for, not who happens to own the scheme this second;
        // Claude takes it back on every launch and the guard puts it right.
        routesHere = guardian.wantsOwnership
    }

    /// True when nothing but our own pid file is in the profile.
    static func profileLooksUnused(_ clone: Clone) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: clone.profileDir)) ?? []
        return contents.filter { $0 != ".instance.pid" }.isEmpty
    }

    var isolationWarning: String? {
        let names = rows.filter(\.isolationSuspect).map(\.clone.displayName)
        guard !names.isEmpty else { return nil }
        return names.count == 1
            ? "\(names[0]) may be sharing the default profile. Quit it, then relaunch from here."
            : "\(names.count) profiles may be sharing the default profile. Quit them, then relaunch from here."
    }

    /// Opening /Applications/Claude.app while a clone runs only activates the clone,
    /// because LaunchServices sees that bundle id as already running. Forcing a new
    /// instance is the only way to reach the default profile.
    func openDefaultProfile() {
        if let pid = defaultPID {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: Paths.claudeApp),
                                           configuration: configuration)
    }

    func open(_ row: Row) {
        if let pid = row.pid {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
        } else {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: row.clone.appPath),
                                               configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func create() {
        let next = (rows.map(\.clone.id).max() ?? 0) + 1
        do {
            let created = try manager.create(name: "Clone \(next)")
            refresh()
            editing = created.id    // land in the row ready to be named
        } catch {
            failure = error.localizedDescription
        }
    }

    func rename(_ clone: Clone, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != clone.name else { editing = nil; return }
        attempt { try manager.rename(clone, to: trimmed) }
        editing = nil
    }

    func confirmDelete(alsoProfile: Bool) {
        guard let clone = pendingDelete else { return }
        manager.delete(clone, includingProfile: alsoProfile)
        pendingDelete = nil
        refresh()
    }

    func reveal(_ clone: Clone) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: clone.profileDir)
    }

    func profileSize(_ clone: Clone) -> String { DiskSize.of(clone.profileDir) }

    func setRouting(_ here: Bool) {
        Task { @MainActor in
            do {
                try await guardian.setWanted(here)
            } catch {
                failure = error.localizedDescription
            }
            refresh()
        }
    }

    /// Called when the popover opens, so drift is corrected before the user notices.
    func recheckSchemeOwnership() {
        Task { @MainActor in
            if await guardian.reassertIfNeeded() { refresh() }
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
            refresh()
        } catch {
            failure = error.localizedDescription
        }
    }
}
