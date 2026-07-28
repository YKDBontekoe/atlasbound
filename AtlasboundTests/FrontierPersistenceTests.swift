import XCTest
@testable import Atlasbound

@MainActor
final class FrontierPersistenceTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-frontier-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testWeeklyRolloverResetsChargeNotDiscovery() {
        let store = TileStore(fileURL: tempURL, installationID: "rollover-test")
        store.upsert(
            WorldTile(
                id: "hex:20:1:0",
                coordinate: TileCoordinate(q: 1, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now,
                weeklyCharge: 3
            )
        )
        store.updateFrontierState({ state in
            var next = state
            next.weekKey = "1999-W01"
            next.weeklyScore = 500
            next.chargedTileIDs = ["hex:20:1:0"]
            return next
        }, playerTile: TileCoordinate(q: 1, r: 0))

        store.applyWeeklyChargeResetIfNeeded()

        XCTAssertEqual(store.tiles["hex:20:1:0"]?.weeklyCharge, 0)
        XCTAssertEqual(store.tiles["hex:20:1:0"]?.state, .discovered)
        XCTAssertEqual(store.frontierState.weeklyScore, 0)
        XCTAssertTrue(store.frontierState.chargedTileIDs.isEmpty)
    }

    func testPersistedPayloadContainsIDsOnly() throws {
        let store = TileStore(fileURL: tempURL, installationID: "payload-test")
        store.updateFrontierState({ state in
            var next = state
            next.weekKey = FrontierEngine.isoWeekKey()
            next.weeklyScore = 42
            return next
        }, playerTile: TileCoordinate(q: 0, r: 0))

        let data = try Data(contentsOf: tempURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let record = object?["frontier"] as? [String: Any] ?? [:]
        let keys = Set(record.keys)
        let allowed: Set<String> = [
            "weekKey", "offers", "activeOfferID", "completedOfferIDs",
            "weeklyScore", "connectionBonusesAwarded", "chargedTileIDs",
            "bestWeekScore", "lifetimeCompletedExpeditions",
        ]
        XCTAssertTrue(keys.isSubset(of: allowed))
        XCTAssertFalse(keys.contains("polygon"))
    }
}
