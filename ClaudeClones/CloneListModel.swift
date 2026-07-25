import AppKit
import SwiftUI

/// View state for the popover. Holds no AppKit or LaunchServices knowledge of its
/// own - it asks the same protocols the CLI uses.
@MainActor
final class CloneListModel: ObservableObject {
    struct Row: Identifiable {
        let clone: Clone
        let pid: pid_t?
        var id: Int { clone.id }
        var isRunning: Bool { pid != nil }
    }

    @Published private(set) var rows: [Row] = []
    @Published var editing: Int?          // clone id being renamed inline
    @Published var pendingDelete: Clone?  // clone awaiting delete confirmation
    @Published var routesHere = false
    @Published var failure: String?

    private let manager: CloneManager
    private let locator: InstanceLocating
    private let scheme = SchemeOwnership()

    init(manager: CloneManager, locator: InstanceLocating) {
        self.manager = manager
        self.locator = locator
    }

    func refresh() {
        rows = manager.clones().map { Row(clone: $0, pid: locator.runningPID(for: $0)) }
        routesHere = scheme.ownedByUs
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
                try await scheme.setOwner(toUs: here)
            } catch {
                failure = error.localizedDescription
            }
            refresh()
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
