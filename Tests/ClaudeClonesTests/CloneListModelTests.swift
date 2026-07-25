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
        model = CloneListModel(manager: manager, locator: StubLocator(running: [1]))
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

    func testRefreshDropsRowsWhoseLauncherDisappeared() throws {
        model.create()
        let row = try XCTUnwrap(model.rows.first)
        try FileManager.default.removeItem(atPath: row.clone.appPath)

        model.refresh()

        XCTAssertTrue(model.rows.isEmpty)
    }
}
