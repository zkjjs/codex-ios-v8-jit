import XCTest
@testable import CodexQuota

final class QuotaTests: XCTestCase {
    func testSideStoreGroupSuffixIsDiscoveredWithoutUnrelatedGroups() throws {
        let group = SharedStore.group
        let profile = try PropertyListSerialization.data(fromPropertyList: [
            "Entitlements": ["com.apple.security.application-groups": ["group.unrelated", group + ".TEAM123"]]
        ], format: .xml, options: 0)
        let cmsFixture = Data([0x30, 0x82, 0x00]) + profile + Data([0x00, 0xff])
        XCTAssertEqual(SharedStore.groupCandidates(metadata: [group], profile: cmsFixture),
                       [group + ".TEAM123", group])
    }

    func testMissingOrMalformedProfileKeepsSafeMetadataFallback() {
        let group = SharedStore.group
        XCTAssertEqual(SharedStore.groupCandidates(metadata: [group + ".TEAM", group + ".TEAM",
                           group + "evil", "group.unrelated"], profile: Data("broken".utf8)),
                       [group + ".TEAM", group])
        XCTAssertEqual(SharedStore.groupCandidates(metadata: [], profile: nil), [group])
    }

    @available(iOS 17.0, *)
    func testAppModeUsesSavedConnectionAndIgnoresManualFields() {
        let saved = ServerConnection(server: "https://saved.example", accessCode: "saved-code")
        let result = WidgetConnectionSelection.resolve(mode: .app, server: "https://old.example",
            accessCode: "old-code", sharedConnection: saved)
        XCTAssertEqual(result.connection?.server, saved.server)
        XCTAssertEqual(result.connection?.accessCode, saved.accessCode)
        XCTAssertFalse(result.manual)
        XCTAssertNil(result.error)
    }

    @available(iOS 17.0, *)
    func testAppModeWithoutSharedConfigurationExplainsMissingSharing() {
        let result = WidgetConnectionSelection.resolve(mode: .app, server: nil,
            accessCode: nil, sharedConnection: nil)
        XCTAssertNil(result.connection)
        XCTAssertTrue(result.error?.contains("共享配置") == true)
    }

    @available(iOS 17.0, *)
    func testManualModeRequiresCodeAndDoesNotUseSavedConnection() {
        let saved = ServerConnection(server: "https://saved.example", accessCode: "saved-code")
        let missing = WidgetConnectionSelection.resolve(mode: .manual, server: nil,
            accessCode: "  ", sharedConnection: saved)
        XCTAssertNil(missing.connection)
        XCTAssertNotNil(missing.error)
        let result = WidgetConnectionSelection.resolve(mode: .manual, server: " https://manual.example ",
            accessCode: " manual-code ", sharedConnection: saved)
        XCTAssertEqual(result.connection?.server, "https://manual.example")
        XCTAssertEqual(result.connection?.accessCode, "manual-code")
        XCTAssertTrue(result.manual)
    }

    func testDecodeRealSnapshotAndMissingReset() throws {
        let data = Data("""
        {"version":1,"updatedAt":100,"stale":false,"plan":"plus","windows":[
        {"id":"primary","title":"5 小时额度","usedPercent":69,"remainingPercent":31,"windowMinutes":300,"resetsAt":null}]}
        """.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 31)
        XCTAssertNil(snapshot.windows[0].resetDate)
        XCTAssertEqual(snapshot.updatedDate, Date(timeIntervalSince1970: 100))
    }

    func testPastResetWaitsForNewData() {
        let window = QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 69,
                                 remainingPercent: 31, windowMinutes: 300, resetsAt: 100)
        XCTAssertTrue(window.awaitingReset(at: Date(timeIntervalSince1970: 101)))
        XCTAssertFalse(window.awaitingReset(at: Date(timeIntervalSince1970: 99)))
        XCTAssertEqual(window.remainingPercent, 31)
    }

    func testMissingWindowsStayEmptyAndStalenessUsesOriginalTime() throws {
        let data = Data(#"{"version":1,"updatedAt":100,"stale":true,"plan":null,"windows":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 101)))
        XCTAssertEqual(snapshot.updatedDate, Date(timeIntervalSince1970: 100))
    }

    func testOldSnapshotIsStaleEvenWithoutServerFlag() throws {
        let data = Data(#"{"version":1,"updatedAt":100,"stale":false,"plan":"plus","windows":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 1100)))
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 101)))
    }

    func testProgressIsBoundedAndMissingConfigurationFails() {
        let window = QuotaWindow(id: "x", title: "x", usedPercent: 0,
                                 remainingPercent: 120, windowMinutes: nil, resetsAt: nil)
        XCTAssertEqual(window.progress, 1)
        XCTAssertThrowsError(try ServerConnection(server: "http://example.com", accessCode: "x").validatedURL())
        XCTAssertThrowsError(try ServerConnection(server: "https://example.com", accessCode: "").validatedURL())
    }

    func testTimelineRetainsTransitionsWhenNetworkRefreshIsDelayed() {
        let snapshot = QuotaSnapshot(version: 1, updatedAt: 100, stale: false, plan: "plus", windows: [
            QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 69,
                        remainingPercent: 31, windowMinutes: 300, resetsAt: 3700)
        ])
        let dates = QuotaSchedule.dates(snapshot: snapshot, now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(dates.map(\.timeIntervalSince1970), [100, 1001, 3701])
    }

    @MainActor
    func testDisconnectDiscardsSuspendedRefresh() async {
        let gate = SuspendedFetch()
        let model = QuotaModel(fetch: { try await gate.fetch($0) })
        model.disconnect()
        model.connection = .init(server: "https://example.com", accessCode: "test")
        let request = Task { await model.refresh() }
        await gate.waitUntilStarted()
        model.disconnect()
        await gate.complete(.preview)
        await request.value
        XCTAssertNil(model.connection)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(SharedStore.loadSnapshot())
    }

    @MainActor
    func testDisconnectDiscardsSuspendedConnectionAttempt() async {
        let gate = SuspendedFetch()
        let model = QuotaModel(fetch: { try await gate.fetch($0) })
        model.disconnect()
        let request = Task { await model.connect(server: "https://example.com", code: "test") }
        await gate.waitUntilStarted()
        model.disconnect()
        await gate.complete(.preview)
        let connected = await request.value
        XCTAssertFalse(connected)
        XCTAssertNil(model.connection)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(SharedStore.loadConnection())
    }
}

private actor SuspendedFetch {
    private var pending: CheckedContinuation<QuotaSnapshot, Error>?
    private var started: CheckedContinuation<Void, Never>?

    func fetch(_ connection: ServerConnection) async throws -> QuotaSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilStarted() async {
        if pending != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func complete(_ snapshot: QuotaSnapshot) {
        pending?.resume(returning: snapshot)
        pending = nil
    }
}
