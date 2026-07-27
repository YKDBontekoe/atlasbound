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

    func testPreUpdateSaveDecodesWithoutFrontierPayload() throws {
        let legacyJSON = """
        {
          "progressBySize": {
            "80": {
              "activitiesCompleted": 2,
              "discoveryXPTotal": 200,
              "familiarityXPTotal": 25,
              "tileSizeMeters": 80
            }
          },
          "tiles": [
            {
              "activityStampsRaw": ["walk"],
              "firstVisitedAt": "2024-01-01T00:00:00Z",
              "id": "hex:80:0:0",
              "lastVisitedAt": "2024-01-02T00:00:00Z",
              "masteryXP": 100,
              "q": 0,
              "r": 0,
              "regionIDs": [],
              "stateRaw": 1,
              "tileSizeMeters": 80,
              "uniqueVisitDays": 1,
              "visitCount": 1,
              "weeklyCharge": 0
            }
          ]
        }
        """
        try legacyJSON.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = TileStore(fileURL: tempURL, installationID: "migration-test")
        store.tileSize = .eighty
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.discoveryXPTotal, 200)
        XCTAssertEqual(store.frontierState.offers.count, 0)
        XCTAssertEqual(store.frontierState.weeklyScore, 0)
    }

    func testFrontierStateIsolatedPerGrid() {
        let store = TileStore(fileURL: tempURL, installationID: "grid-test")

        store.tileSize = .sixty
        store.updateFrontierState({ state in
            var next = state
            next.weeklyScore = 120
            return next
        }, playerTile: TileCoordinate(q: 0, r: 0))

        store.tileSize = .hundred
        XCTAssertEqual(store.frontierState.weeklyScore, 0)

        store.tileSize = .sixty
        XCTAssertEqual(store.frontierState.weeklyScore, 120)
    }

    func testWeeklyRolloverResetsChargeNotDiscovery() {
        let store = TileStore(fileURL: tempURL, installationID: "rollover-test")
        store.tileSize = .eighty
        store.upsert(
            WorldTile(
                id: "hex:80:1:0",
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
            next.chargedTileIDs = ["hex:80:1:0"]
            return next
        }, playerTile: TileCoordinate(q: 1, r: 0))

        store.applyWeeklyChargeResetIfNeeded()

        XCTAssertEqual(store.tiles["hex:80:1:0"]?.weeklyCharge, 0)
        XCTAssertEqual(store.tiles["hex:80:1:0"]?.state, .discovered)
        XCTAssertEqual(store.frontierState.weeklyScore, 0)
        XCTAssertTrue(store.frontierState.chargedTileIDs.isEmpty)
    }

    func testPersistedPayloadContainsIDsOnly() throws {
        let store = TileStore(fileURL: tempURL, installationID: "payload-test")
        store.tileSize = .eighty
        store.updateFrontierState({ state in
            var next = state
            next.weekKey = FrontierEngine.isoWeekKey()
            next.weeklyScore = 42
            return next
        }, playerTile: TileCoordinate(q: 0, r: 0))

        let data = try Data(contentsOf: tempURL)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let frontier = object?["frontierBySize"] as? [String: Any]
        let record = (frontier?["80"] as? [String: Any]) ?? [:]
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
