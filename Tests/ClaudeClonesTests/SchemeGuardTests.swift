import XCTest
@testable import ClaudeClonesCore

/// Claude re-registers itself for claude:// on every launch, so ownership drifts
/// away silently. These cover the logic that puts it back.
@MainActor
final class SchemeGuardTests: XCTestCase {
    final class SpyOwnership: SchemeOwning {
        var owned = false
        var calls: [Bool] = []
        var throwsNext = false
        struct Boom: Error {}

        var ownedByUs: Bool { owned }

        func setOwner(toUs: Bool) async throws {
            calls.append(toUs)
            if throwsNext {
                throwsNext = false
                throw Boom()
            }
            owned = toUs
        }
    }

    private var ownership: SpyOwnership!
    private var defaults: UserDefaults!
    private var guardian: SchemeGuard!

    override func setUp() {
        super.setUp()
        ownership = SpyOwnership()
        defaults = UserDefaults(suiteName: "claudeclones.tests.\(UUID().uuidString)")!
        guardian = SchemeGuard(ownership: ownership, defaults: defaults)
    }

    override func tearDown() {
        guardian = nil
        defaults = nil
        ownership = nil
        super.tearDown()
    }

    func testDefaultsToNotWantingOwnership() {
        XCTAssertFalse(guardian.wantsOwnership)
    }

    func testSetWantedRecordsIntentAndClaims() async throws {
        try await guardian.setWanted(true)

        XCTAssertTrue(guardian.wantsOwnership)
        XCTAssertEqual(ownership.calls, [true])
        XCTAssertTrue(ownership.ownedByUs)
    }

    func testSetWantedFalseHandsTheSchemeBack() async throws {
        try await guardian.setWanted(true)
        try await guardian.setWanted(false)

        XCTAssertFalse(guardian.wantsOwnership)
        XCTAssertEqual(ownership.calls, [true, false])
    }

    /// The intent must persist even when the claim itself fails, otherwise the
    /// toggle silently forgets what the user asked for.
    func testIntentSurvivesAFailedClaim() async {
        ownership.throwsNext = true

        do {
            try await guardian.setWanted(true)
            XCTFail("expected the claim to throw")
        } catch {
            XCTAssertTrue(guardian.wantsOwnership)
        }
    }

    func testReassertReclaimsWhenSomethingElseTookTheScheme() async throws {
        try await guardian.setWanted(true)
        ownership.owned = false      // Claude launched and took it
        ownership.calls = []

        let reclaimed = await guardian.reassertIfNeeded()

        XCTAssertTrue(reclaimed)
        XCTAssertEqual(ownership.calls, [true])
        XCTAssertTrue(ownership.ownedByUs)
    }

    func testReassertDoesNothingWhenAlreadyOwned() async throws {
        try await guardian.setWanted(true)
        ownership.calls = []

        let reclaimed = await guardian.reassertIfNeeded()

        XCTAssertFalse(reclaimed)
        XCTAssertTrue(ownership.calls.isEmpty)
    }

    /// The user turned routing off, so drift is what they asked for.
    func testReassertRespectsTheUserTurningRoutingOff() async {
        ownership.owned = false

        let reclaimed = await guardian.reassertIfNeeded()

        XCTAssertFalse(reclaimed)
        XCTAssertTrue(ownership.calls.isEmpty)
    }

    /// A single delayed check loses whenever Claude registers later than expected,
    /// which is machine and cold-start dependent, so a launch gets several attempts
    /// spread over enough time to outlast a slow startup.
    func testLaunchIsAnsweredWithSeveralSpreadOutAttempts() {
        XCTAssertGreaterThanOrEqual(SchemeGuard.reclaimDelays.count, 3)
        XCTAssertEqual(SchemeGuard.reclaimDelays, SchemeGuard.reclaimDelays.sorted())
        XCTAssertGreaterThanOrEqual(SchemeGuard.reclaimDelays.last ?? 0, 20,
                                    "must still be checking well after a slow launch")
    }

    func testPollerRunsOftenEnoughToBeABackstop() {
        XCTAssertLessThanOrEqual(SchemeGuard.pollInterval, 60)
    }

    func testReassertReportsFailureWithoutCrashing() async throws {
        try await guardian.setWanted(true)
        ownership.owned = false
        ownership.throwsNext = true

        let reclaimed = await guardian.reassertIfNeeded()

        XCTAssertFalse(reclaimed)
        XCTAssertTrue(guardian.wantsOwnership, "intent is unchanged by a failed reclaim")
    }
}

final class RedactTests: XCTestCase {
    func testQueryValuesAreRemovedButNamesKept() {
        let redacted = Redact.link("claude://claude.ai/magic-link?token=supersecret")

        XCTAssertFalse(redacted.contains("supersecret"))
        XCTAssertTrue(redacted.contains("token="))
        XCTAssertTrue(redacted.contains("claude.ai/magic-link"))
    }

    func testEverySecretInAMultiParameterLinkGoes() {
        let redacted = Redact.link("claude://claude.ai/mcp-auth-callback/sdk"
                                   + "?code=abc123&state=xyz789")

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz789"))
        XCTAssertTrue(redacted.contains("code="))
        XCTAssertTrue(redacted.contains("state="))
    }

    func testSessionIdentifiersAreTreatedAsPrivate() {
        let redacted = Redact.link("claude://resume?session=cafe1111-1111-4111-8111-cafe11111111")

        XCTAssertFalse(redacted.contains("cafe1111"))
        XCTAssertTrue(redacted.hasPrefix("claude://resume?session="))
    }

    func testCredentialsAndFragmentsGo() {
        let redacted = Redact.link("claude://user:pass@claude.ai/x#fragmentsecret")

        XCTAssertFalse(redacted.contains("pass"))
        XCTAssertFalse(redacted.contains("fragmentsecret"))
    }

    func testLinksWithoutAQuerySurviveIntact() {
        XCTAssertEqual(Redact.link("claude://cowork/shared-artifact"),
                       "claude://cowork/shared-artifact")
    }

    func testGarbageInputStillYieldsNoSecret() {
        XCTAssertEqual(Redact.link("not a url at all"), Redact.unrecognized)
    }
}

/// Identifying Claude by bundle id alone missed clones: a wrapper bundle registers
/// under its own id while running the very same Claude binary.
final class ClaudeProcessMatchingTests: XCTestCase {
    func testMatchesTheStockAppByBundleID() {
        XCTAssertEqual(claudeBundleID, "com.anthropic.claudefordesktop")
    }

    func testTheBinaryPathIsTheOtherSignal() {
        XCTAssertEqual(Paths.claudeBinary, "/Applications/Claude.app/Contents/MacOS/Claude")
        XCTAssertTrue(Paths.claudeBinary.hasPrefix(Paths.claudeApp))
    }
}
