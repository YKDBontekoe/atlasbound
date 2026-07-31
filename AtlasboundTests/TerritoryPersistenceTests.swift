import XCTest
@testable import Atlasbound

@MainActor
final class TerritoryPersistenceTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-territory-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-shm"))
        tempURL = nil
        super.tearDown()
    }

    func testTerritoryRoundTripAndClear() {
        let store = TileStore(fileURL: tempURL, installationID: "territory-test")
        let claimedAt = Date(timeIntervalSince1970: 1_700_000_100)
        store.updateTerritoryState { _ in
            TerritoryState(
                homeSectorID: "sector:20:0:0",
                claims: [
                    TerritoryClaim(sectorID: "sector:20:0:0", claimedAt: claimedAt),
                    TerritoryClaim(sectorID: "sector:20:1:0", claimedAt: claimedAt),
                ],
                homeMovedAt: claimedAt
            )
        }

        let reloaded = TileStore(fileURL: tempURL, installationID: "territory-test")
        XCTAssertEqual(reloaded.territoryState.homeSectorID, "sector:20:0:0")
        XCTAssertEqual(reloaded.territoryState.claimCount, 2)
        XCTAssertEqual(reloaded.territoryState.claims.map(\.sectorID).sorted(), [
            "sector:20:0:0",
            "sector:20:1:0",
        ])

        reloaded.clearAtlas()
        XCTAssertEqual(reloaded.territoryState, .empty)

        let afterClear = TileStore(fileURL: tempURL, installationID: "territory-test")
        XCTAssertEqual(afterClear.territoryState, .empty)
    }

    func testPersistedTerritoryPayloadContainsIDsOnly() throws {
        let store = TileStore(fileURL: tempURL, installationID: "payload-test")
        store.updateTerritoryState { _ in
            TerritoryState(
                homeSectorID: "sector:20:2:-1",
                claims: [TerritoryClaim(sectorID: "sector:20:2:-1", claimedAt: .now)],
                homeMovedAt: .now
            )
        }

        let reloaded = TileStore(fileURL: tempURL, installationID: "payload-test")
        let record = PersistedTerritoryRecord(from: reloaded.territoryState)
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let keys = Set(object.keys)
        let allowed: Set<String> = ["homeSectorID", "claims", "homeMovedAt"]
        XCTAssertTrue(keys.isSubset(of: allowed))
        XCTAssertFalse(keys.contains("polygon"))
        XCTAssertFalse(keys.contains("latitude"))

        if let claims = object["claims"] as? [[String: Any]], let first = claims.first {
            let claimKeys = Set(first.keys)
            XCTAssertTrue(claimKeys.isSubset(of: ["sectorID", "claimedAt"]))
            XCTAssertFalse(claimKeys.contains("polygon"))
        } else {
            XCTFail("Expected claims array in payload")
        }
    }

    func testSchemaCreatesTerritoryTableOnFreshDatabase() {
        let database = AtlasDatabase.makeIsolated(fileURL: tempURL)
        database.saveTerritory(
            TerritoryState(
                homeSectorID: "sector:20:0:0",
                claims: [TerritoryClaim(sectorID: "sector:20:0:0", claimedAt: .now)],
                homeMovedAt: .now
            )
        )
        let loaded = database.loadTerritory()
        XCTAssertEqual(loaded.homeSectorID, "sector:20:0:0")
        XCTAssertEqual(loaded.claimCount, 1)
    }
}
