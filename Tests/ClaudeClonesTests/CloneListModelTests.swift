import XCTest
@testable import ClaudeClonesCore

@MainActor
final class CloneListModelTests: XCTestCase {
    private var sandbox: Sandbox!
    private var provisioner: SpyProvisioner!
    private var model: CloneListModel!

    override func setUp() {
        super.setUp()
        sandbox = Sandbox("model")
        provisioner = SpyProvisioner()
        let manager = CloneManager(store: sandbox.store(),
                                   builder: provisioner,
                                   layout: sandbox.layout)
        let defaults = UserDefaults(suiteName: "claudeclones.model.\(UUID().uuidString)")!
        model = CloneListModel(manager: manager,
                               locator: StubLocator(running: [1]),
                               guardian: SchemeGuard(ownership: StubOwnership(),
                                                     defaults: defaults))
    }

    override func tearDown() {
        model = nil
        provisioner = nil
        sandbox = nil
        super.tearDown()
    }

    func testStartsEmpty() {
        model.refresh()

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.failure)
    }

    func testCreateAddsARowAndOpensItForRenaming() {
        model.create()

        XCTAssertEqual(model.rows.map(\.clone.name), ["Clone 1"])
        XCTAssertEqual(model.editing, model.rows.first?.id,
                       "a new row should land in inline rename")
        XCTAssertNil(model.failure)
    }

    func testRowsReportRunningStateFromTheLocator() {
        model.create()   // id 1, which the stub locator reports as running
        model.create()   // id 2, stopped

        XCTAssertEqual(model.rows.map(\.isRunning), [true, false])
        XCTAssertEqual(model.rows.first?.pid, 4242)
    }

    func testCreateSurfacesFailuresInsteadOfCrashing() {
        provisioner.failNextProvision = true

        model.create()

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNotNil(model.failure)
    }

    func testRenameUpdatesTheRowAndClosesTheEditor() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)

        model.rename(row.clone, to: "Work")

        XCTAssertEqual(model.rows.map(\.clone.name), ["Work"])
        XCTAssertNil(model.editing)
    }

    func testRenameTrimsWhitespace() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)

        model.rename(row.clone, to: "  Padded  ")

        XCTAssertEqual(model.rows.map(\.clone.name), ["Padded"])
    }

    func testRenameToBlankIsIgnored() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)

        model.rename(row.clone, to: "   ")

        XCTAssertEqual(model.rows.map(\.clone.name), ["Clone 1"])
        XCTAssertNil(model.editing, "the editor should close either way")
    }

    func testDeleteNeedsAPendingCloneAndThenRemovesIt() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)

        model.confirmDelete(alsoProfile: false)   // nothing pending yet
        XCTAssertEqual(model.rows.count, 1)

        model.pendingDelete = row.clone
        model.confirmDelete(alsoProfile: true)

        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.pendingDelete)
        XCTAssertEqual(provisioner.removed.map(\.profile), [true])
    }

    /// A running clone whose profile stayed empty means CLAUDE_USER_DATA_DIR was
    /// ignored and it is quietly sharing the default profile.
    func testRunningCloneWithAnEmptyProfileIsFlagged() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)
        for entry in (try? FileManager.default.contentsOfDirectory(atPath: row.clone.profileDir)) ?? [] {
            try FileManager.default.removeItem(atPath: row.clone.profileDir + "/" + entry)
        }

        model.refresh()

        XCTAssertTrue(model.rows.first?.isolationSuspect == true)
        XCTAssertNotNil(model.isolationWarning)
        XCTAssertTrue(model.isolationWarning?.contains("Claude Clone 1") == true)
    }

    func testAPidFileAloneDoesNotCountAsUsedProfile() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)
        FileManager.default.createFile(atPath: row.clone.pidFile, contents: Data("42".utf8))

        model.refresh()

        XCTAssertTrue(model.rows.first?.isolationSuspect == true)
    }

    func testProfileWithDataIsNotFlagged() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)
        FileManager.default.createFile(atPath: row.clone.profileDir + "/Cookies",
                                      contents: Data("x".utf8))

        model.refresh()

        XCTAssertFalse(model.rows.first?.isolationSuspect == true)
        XCTAssertNil(model.isolationWarning)
    }

    func testStoppedCloneIsNeverFlagged() throws {
        model.create()   // id 1 runs
        model.create()   // id 2 is stopped, and its profile is empty

        model.refresh()

        XCTAssertFalse(model.rows.last?.isolationSuspect == true)
    }

    func testDefaultProfilePIDComesFromTheLocator() {
        model.refresh()

        XCTAssertEqual(model.defaultPID, 1)
    }

    func testRefreshDropsRowsWhoseLauncherDisappeared() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)
        try FileManager.default.removeItem(atPath: row.clone.appPath)

        model.refresh()

        XCTAssertTrue(model.rows.isEmpty)
    }
}
