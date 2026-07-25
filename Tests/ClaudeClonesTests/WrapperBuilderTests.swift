import XCTest
@testable import ClaudeClonesCore

/// The wrapper's Info.plist and launch script encode three hard-won macOS
/// behaviours. These assertions exist so a future edit cannot quietly undo them.
final class WrapperBuilderTests: XCTestCase {
    private var sandbox: Sandbox!
    private var registrar: SpyRegistrar!
    private var builder: AppWrapperBuilder!
    private var clone: Clone!

    override func setUp() {
        super.setUp()
        sandbox = Sandbox("wrapper")
        registrar = SpyRegistrar()
        builder = AppWrapperBuilder(icons: NoIcons(), launchServices: registrar)
        clone = Clone(id: 2,
                      name: "Work",
                      profileDir: sandbox.layout.profile(id: 2),
                      appPath: sandbox.layout.app(named: "Work"))
    }

    override func tearDown() {
        builder = nil
        registrar = nil
        sandbox = nil
        clone = nil
        super.tearDown()
    }

    private func provision() throws -> (plist: String, script: String) {
        try builder.provision(clone)
        return (sandbox.read(clone.appPath + "/Contents/Info.plist"),
                sandbox.read(clone.appPath + "/Contents/MacOS/run"))
    }

    func testProvisionCreatesBundleAndProfile() throws {
        try builder.provision(clone)

        XCTAssertTrue(sandbox.exists(clone.appPath + "/Contents/Info.plist"))
        XCTAssertTrue(sandbox.exists(clone.appPath + "/Contents/MacOS/run"))
        XCTAssertTrue(sandbox.exists(clone.profileDir))
        XCTAssertEqual(registrar.registered, [clone.appPath])
    }

    func testScriptIsExecutable() throws {
        try builder.provision(clone)

        let attributes = try FileManager.default
            .attributesOfItem(atPath: clone.appPath + "/Contents/MacOS/run")
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o755)
    }

    func testPlistIsValidAndCarriesIdentity() throws {
        let (plist, _) = try provision()
        let data = Data(plist.utf8)
        let parsed = try PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any]

        XCTAssertEqual(parsed?["CFBundleIdentifier"] as? String, "com.local.claude.clone2")
        XCTAssertEqual(parsed?["CFBundleName"] as? String, "Claude Work")
        XCTAssertEqual(parsed?["CFBundleExecutable"] as? String, "run")
    }

    /// A bundle declaring LSEnvironment fails to launch at all on macOS 26
    /// (LSOpenURLs error -54), so the key must stay absent.
    func testPlistDeclaresNoLSEnvironment() throws {
        let (plist, _) = try provision()

        XCTAssertFalse(plist.contains("LSEnvironment"))
    }

    /// Without this the script based bundle launches as x86_64 and Claude runs under
    /// Rosetta, which renders a blank window.
    func testPlistForcesArm64() throws {
        let (plist, _) = try provision()
        let parsed = try PropertyListSerialization
            .propertyList(from: Data(plist.utf8), format: nil) as? [String: Any]

        XCTAssertEqual(parsed?["LSArchitecturePriority"] as? [String], ["arm64"])
    }

    func testScriptExportsTheProfileAndExecsClaude() throws {
        let (_, script) = try provision()

        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
        XCTAssertTrue(script.contains("export CLAUDE_USER_DATA_DIR=\"\(clone.profileDir)\""))
        XCTAssertTrue(script.contains("exec \(Paths.claudeBinary)"))
    }

    /// A second process on one profile comes up signed out, so the script must focus
    /// the running instance instead of launching again.
    func testScriptFocusesAnAlreadyRunningInstance() throws {
        let (_, script) = try provision()

        XCTAssertTrue(script.contains("$CLAUDE_USER_DATA_DIR/.instance.pid"))
        XCTAssertTrue(script.contains("echo $$ > \"$pidfile\""),
                      "must record its own pid, which exec preserves")
        XCTAssertTrue(script.contains("set frontmost of"))
        XCTAssertTrue(script.contains("exit 0"))
    }

    func testGeneratedScriptIsValidBash() throws {
        try builder.provision(clone)

        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/bin/bash")
        check.arguments = ["-n", clone.appPath + "/Contents/MacOS/run"]
        try check.run()
        check.waitUntilExit()

        XCTAssertEqual(check.terminationStatus, 0, "bash -n rejected the generated script")
    }

    func testMoveRelocatesBundleAndUnregistersOldPath() throws {
        try builder.provision(clone)
        let destination = sandbox.layout.app(named: "Personal")

        try builder.move(clone, to: destination)

        XCTAssertTrue(sandbox.exists(destination))
        XCTAssertFalse(sandbox.exists(clone.appPath))
        XCTAssertEqual(registrar.unregistered, [clone.appPath])
    }

    func testRemoveKeepsProfileUnlessAsked() throws {
        try builder.provision(clone)

        builder.remove(clone, includingProfile: false)

        XCTAssertFalse(sandbox.exists(clone.appPath))
        XCTAssertTrue(sandbox.exists(clone.profileDir))
    }

    func testRemoveWithProfileDeletesBoth() throws {
        try builder.provision(clone)

        builder.remove(clone, includingProfile: true)

        XCTAssertFalse(sandbox.exists(clone.appPath))
        XCTAssertFalse(sandbox.exists(clone.profileDir))
    }
}
