import XCTest
@testable import ClaudeClonesCore

final class CloneManagerTests: XCTestCase {
    private var sandbox: Sandbox!
    private var provisioner: SpyProvisioner!
    private var manager: CloneManager!

    override func setUp() {
        super.setUp()
        sandbox = Sandbox("manager")
        provisioner = SpyProvisioner()
        manager = CloneManager(store: sandbox.store(), builder: provisioner, layout: sandbox.layout)
    }

    override func tearDown() {
        manager = nil
        provisioner = nil
        sandbox = nil
        super.tearDown()
    }

    func testCreateAssignsPathsFromLayout() throws {
        let clone = try manager.create(name: "Work")

        XCTAssertEqual(clone.id, 1)
        XCTAssertEqual(clone.appPath, sandbox.layout.applications + "/Claude Work.app")
        XCTAssertEqual(clone.profileDir, sandbox.layout.instancesRoot + "/clone-1")
        XCTAssertEqual(clone.displayName, "Claude Work")
        XCTAssertEqual(manager.clones().map(\.name), ["Work"])
    }

    func testCreateNumbersSequentially() throws {
        try manager.create(name: "One")
        try manager.create(name: "Two")

        XCTAssertEqual(manager.clones().map(\.id), [1, 2])
    }

    /// Regression: an id that collides with a leftover directory would point a new
    /// clone at another account's login. This is what destroyed a real profile.
    func testCreateSkipsIDsWithProfileDirectoriesOnDisk() throws {
        sandbox.makeProfileDir(id: 1)
        sandbox.makeProfileDir(id: 2)

        let clone = try manager.create(name: "Fresh")

        XCTAssertEqual(clone.id, 3)
        XCTAssertEqual(clone.profileDir, sandbox.layout.instancesRoot + "/clone-3")
    }

    func testCreateSkipsIDsEvenWhenStoreIsEmpty() throws {
        sandbox.makeProfileDir(id: 7)

        XCTAssertEqual(try manager.create(name: "After Seven").id, 8)
    }

    func testFailedProvisionLeavesNothingBehind() {
        provisioner.failNextProvision = true

        XCTAssertThrowsError(try manager.create(name: "Doomed"))
        XCTAssertTrue(manager.clones().isEmpty)
    }

    func testClonesPrunesEntriesWhoseBundleIsGone() throws {
        let keep = try manager.create(name: "Keep")
        let drop = try manager.create(name: "Drop")
        try FileManager.default.removeItem(atPath: drop.appPath)

        XCTAssertEqual(manager.clones().map(\.id), [keep.id])
        // The prune is persisted, not just filtered on read.
        XCTAssertEqual(sandbox.store().load().map(\.id), [keep.id])
    }

    /// Regression: renaming used to write through the pruning read, so the entry
    /// vanished the moment its old bundle path stopped existing.
    func testRenameKeepsTheCloneAndUpdatesPaths() throws {
        let clone = try manager.create(name: "Before")

        try manager.rename(clone, to: "After")

        let all = manager.clones()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "After")
        XCTAssertEqual(all.first?.appPath, sandbox.layout.app(named: "After"))
        XCTAssertEqual(all.first?.id, clone.id, "id must survive a rename")
        XCTAssertEqual(all.first?.profileDir, clone.profileDir, "profile must not move")
        XCTAssertTrue(sandbox.exists(sandbox.layout.app(named: "After")))
        XCTAssertFalse(sandbox.exists(sandbox.layout.app(named: "Before")))
    }

    func testRenameToSameNameDoesNotMoveTheBundle() throws {
        let clone = try manager.create(name: "Same")

        try manager.rename(clone, to: "Same")

        XCTAssertTrue(provisioner.moved.isEmpty)
        XCTAssertEqual(manager.clones().map(\.name), ["Same"])
    }

    func testRenamePreservesOtherClones() throws {
        let first = try manager.create(name: "First")
        let second = try manager.create(name: "Second")

        try manager.rename(first, to: "Renamed")

        XCTAssertEqual(manager.clones().map(\.name).sorted(), ["Renamed", "Second"])
        XCTAssertTrue(sandbox.exists(second.appPath))
    }

    func testDeleteRemovesEntryAndLauncherButKeepsProfileByDefault() throws {
        let clone = try manager.create(name: "Temp")

        manager.delete(clone, includingProfile: false)

        XCTAssertTrue(manager.clones().isEmpty)
        XCTAssertFalse(sandbox.exists(clone.appPath))
        XCTAssertTrue(sandbox.exists(clone.profileDir), "profile data must survive")
        XCTAssertEqual(provisioner.removed.map(\.profile), [false])
    }

    func testDeleteWithProfileRemovesTheData() throws {
        let clone = try manager.create(name: "Temp")

        manager.delete(clone, includingProfile: true)

        XCTAssertFalse(sandbox.exists(clone.profileDir))
    }

    func testDeleteLeavesSiblingsAlone() throws {
        let doomed = try manager.create(name: "Doomed")
        let survivor = try manager.create(name: "Survivor")

        manager.delete(doomed, includingProfile: true)

        XCTAssertEqual(manager.clones().map(\.name), ["Survivor"])
        XCTAssertTrue(sandbox.exists(survivor.appPath))
        XCTAssertTrue(sandbox.exists(survivor.profileDir))
    }

    /// A deleted clone's directory number must not be recycled afterwards.
    func testIDsAreNotRecycledAfterDeletingTheLauncherOnly() throws {
        let first = try manager.create(name: "First")
        manager.delete(first, includingProfile: false)

        XCTAssertEqual(try manager.create(name: "Second").id, 2)
    }
}
