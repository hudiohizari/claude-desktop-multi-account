import Foundation
import XCTest
@testable import ClaudeClonesCore

/// A sandbox under the temp directory, so nothing in these tests can reach
/// ~/Applications, ~/.claude-instances or the LaunchServices database.
final class Sandbox {
    let root: String
    let layout: Layout

    init(_ name: String) {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudeclones-tests-\(name)-\(UUID().uuidString)").path
        layout = Layout(applications: root + "/Applications",
                        instancesRoot: root + "/instances")
        try? FileManager.default.createDirectory(atPath: layout.applications,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: layout.instancesRoot,
                                                withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    var storeFile: String { root + "/clones.json" }
    func store() -> JSONCloneStore { JSONCloneStore(file: storeFile) }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func makeProfileDir(id: Int) {
        try? FileManager.default.createDirectory(atPath: layout.profile(id: id),
                                                 withIntermediateDirectories: true)
    }

    func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }
}

/// Records what it was asked to do and creates the bundle directory, which
/// `CloneManager.clones()` requires to exist.
final class SpyProvisioner: CloneProvisioning {
    var provisioned: [Clone] = []
    var moved: [(from: String, to: String)] = []
    var removed: [(clone: Clone, profile: Bool)] = []
    var failNextProvision = false

    struct Boom: Error {}

    func provision(_ clone: Clone) throws {
        if failNextProvision {
            failNextProvision = false
            throw Boom()
        }
        provisioned.append(clone)
        try? FileManager.default.createDirectory(atPath: clone.appPath,
                                                withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: clone.profileDir,
                                                withIntermediateDirectories: true)
    }

    func move(_ clone: Clone, to newPath: String) throws {
        moved.append((clone.appPath, newPath))
        try? FileManager.default.removeItem(atPath: newPath)
        try FileManager.default.moveItem(atPath: clone.appPath, toPath: newPath)
    }

    func remove(_ clone: Clone, includingProfile: Bool) {
        removed.append((clone, includingProfile))
        try? FileManager.default.removeItem(atPath: clone.appPath)
        if includingProfile { try? FileManager.default.removeItem(atPath: clone.profileDir) }
    }
}

struct StubLocator: InstanceLocating {
    var running: Set<Int> = []
    func runningPID(for clone: Clone) -> pid_t? { running.contains(clone.id) ? 4242 : nil }
    func defaultProfilePID(excluding clones: [Clone]) -> pid_t? { 1 }
}

struct NoIcons: IconRendering {
    func badge(_ clone: Clone) {}
}

final class SpyRegistrar: BundleRegistering {
    var registered: [String] = []
    var unregistered: [String] = []
    func register(_ path: String) { registered.append(path) }
    func unregister(_ path: String) { unregistered.append(path) }
}
