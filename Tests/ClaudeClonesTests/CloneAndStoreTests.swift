import XCTest
@testable import ClaudeClonesCore

final class CloneTests: XCTestCase {
    private func clone(id: Int = 1, name: String) -> Clone {
        Clone(id: id, name: name, profileDir: "/tmp/p", appPath: "/tmp/a.app")
    }

    func testBadgeIsTheUppercasedInitial() {
        XCTAssertEqual(clone(name: "work").badgeText, "W")
        XCTAssertEqual(clone(name: "Personal").badgeText, "P")
    }

    func testBadgeIgnoresLeadingWhitespace() {
        XCTAssertEqual(clone(name: "   spaced").badgeText, "S")
    }

    func testBadgeFallsBackToTheIDWhenNameHasNoLetters() {
        XCTAssertEqual(clone(id: 4, name: "   ").badgeText, "4")
        XCTAssertEqual(clone(id: 9, name: "").badgeText, "9")
    }

    func testBadgeHandlesNonLatinNames() {
        XCTAssertEqual(clone(name: "работа").badgeText, "Р")
        XCTAssertEqual(clone(name: "日本").badgeText, "日")
    }

    func testDisplayNameAndBundleID() {
        let value = clone(id: 3, name: "Client A")
        XCTAssertEqual(value.displayName, "Claude Client A")
        XCTAssertEqual(value.bundleID, "com.local.claude.clone3")
    }

    func testPidFileSitsInsideTheProfile() {
        let value = Clone(id: 1, name: "x", profileDir: "/tmp/profile", appPath: "/tmp/a.app")
        XCTAssertEqual(value.pidFile, "/tmp/profile/.instance.pid")
    }
}

final class LayoutTests: XCTestCase {
    private var sandbox: Sandbox!

    override func setUp() {
        super.setUp()
        sandbox = Sandbox("layout")
    }

    override func tearDown() {
        sandbox = nil
        super.tearDown()
    }

    func testPathsAreDerivedFromTheRoots() {
        XCTAssertEqual(sandbox.layout.app(named: "Work"),
                       sandbox.layout.applications + "/Claude Work.app")
        XCTAssertEqual(sandbox.layout.profile(id: 5),
                       sandbox.layout.instancesRoot + "/clone-5")
    }

    func testProfileIDsOnDiskIgnoresUnrelatedEntries() {
        sandbox.makeProfileDir(id: 2)
        sandbox.makeProfileDir(id: 10)
        try? FileManager.default.createDirectory(
            atPath: sandbox.layout.instancesRoot + "/not-a-clone", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: sandbox.layout.instancesRoot + "/clones.json",
                                      contents: Data("[]".utf8))

        XCTAssertEqual(sandbox.layout.profileIDsOnDisk().sorted(), [2, 10])
    }

    func testProfileIDsOnDiskIsEmptyWhenRootIsMissing() {
        let layout = Layout(applications: "/nope", instancesRoot: "/nope/instances")
        XCTAssertTrue(layout.profileIDsOnDisk().isEmpty)
    }
}

final class JSONCloneStoreTests: XCTestCase {
    private var sandbox: Sandbox!

    override func setUp() {
        super.setUp()
        sandbox = Sandbox("store")
    }

    override func tearDown() {
        sandbox = nil
        super.tearDown()
    }

    func testRoundTrip() {
        let clones = [
            Clone(id: 1, name: "Work", profileDir: "/p/1", appPath: "/a/1.app"),
            Clone(id: 2, name: "Home", profileDir: "/p/2", appPath: "/a/2.app"),
        ]
        let store = sandbox.store()

        store.save(clones)

        XCTAssertEqual(store.load(), clones)
    }

    func testLoadIsEmptyWhenFileIsMissing() {
        XCTAssertTrue(JSONCloneStore(file: sandbox.root + "/absent.json").load().isEmpty)
    }

    func testLoadIsEmptyWhenFileIsCorrupt() {
        let path = sandbox.root + "/corrupt.json"
        FileManager.default.createFile(atPath: path, contents: Data("{ not json".utf8))

        XCTAssertTrue(JSONCloneStore(file: path).load().isEmpty)
    }

    func testSaveCreatesMissingDirectories() {
        let store = JSONCloneStore(file: sandbox.root + "/nested/deeper/clones.json")

        store.save([Clone(id: 1, name: "X", profileDir: "/p", appPath: "/a.app")])

        XCTAssertEqual(store.load().count, 1)
    }

    func testSaveOverwritesRatherThanAppends() {
        let store = sandbox.store()
        store.save([Clone(id: 1, name: "First", profileDir: "/p", appPath: "/a.app")])
        store.save([Clone(id: 2, name: "Second", profileDir: "/p", appPath: "/a.app")])

        XCTAssertEqual(store.load().map(\.name), ["Second"])
    }
}
