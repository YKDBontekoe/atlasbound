import XCTest
@testable import Atlasbound

@MainActor
final class WorldEventPersistenceTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-events-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testPreUpdateSaveDecodesWithoutEventsPayload() throws {
        let legacyJSON = """
        {
          "progressBySize": {
            "20": {
              "activitiesCompleted": 1,
              "discoveryXPTotal": 100,
              "familiarityXPTotal": 0,
              "tileSizeMeters": 20
            }
          },
          "tiles": [
            {
              "activityStampsRaw": ["walk"],
              "firstVisitedAt": "2024-01-01T00:00:00Z",
              "id": "hex:20:0:0",
              "lastVisitedAt": "2024-01-02T00:00:00Z",
              "masteryXP": 100,
              "q": 0,
              "r": 0,
              "regionIDs": [],
              "stateRaw": 1,
              "tileSizeMeters": 20,
              "uniqueVisitDays": 1,
              "visitCount": 1,
              "weeklyCharge": 0
            }
          ]
        }
        """
        try legacyJSON.write(to: tempURL, atomically: true, encoding: .utf8)

        let store = TileStore(fileURL: tempURL, installationID: "migration-events")
        store.tileSize = .twenty
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.worldEventState.dayKey, "")
        XCTAssertTrue(store.worldEventState.dailyHotspotTileIDs.isEmpty)
    }

    func testWorldEventStateIsolatedPerGrid() {
        let store = TileStore(fileURL: tempURL, installationID: "grid-events")

        store.tileSize = .fifteen
        store.updateWorldEventState({ state in
            var next = state
            next.dayKey = "2026-07-28"
            next.lifetimeEventsCompleted = 3
            next.dailyHotspotTileIDs = ["hex:15:1:1"]
            return next
        }, playerTile: TileCoordinate(q: 0, r: 0))

        store.tileSize = .twentyFive
        XCTAssertEqual(store.worldEventState.lifetimeEventsCompleted, 0)

        store.tileSize = .fifteen
        XCTAssertEqual(store.worldEventState.lifetimeEventsCompleted, 3)
        XCTAssertEqual(store.worldEventState.dailyHotspotTileIDs, ["hex:15:1:1"])
    }

    func testClearCurrentGridWipesEvents() {
        let store = TileStore(fileURL: tempURL, installationID: "clear-events")
        store.tileSize = .twenty
        store.updateWorldEventState({ state in
            var next = state
            next.dayKey = "2026-07-28"
            next.lifetimeEventsCompleted = 2
            next.dailyHotspotTileIDs = ["hex:20:2:2"]
            return next
        }, playerTile: TileCoordinate(q: 0, r: 0))

        store.clearCurrentGrid()
        XCTAssertEqual(store.worldEventState, .empty)
    }
}
