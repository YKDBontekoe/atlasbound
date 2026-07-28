import XCTest
@testable import Atlasbound

final class PersistenceGeometryTests: XCTestCase {
    func testPersistedTileRecordRoundTrip() throws {
        let original = WorldTile(
            id: "hex:20:4:-2",
            coordinate: TileCoordinate(q: 4, r: -2),
            state: .surveyed,
            masteryXP: 220,
            visitCount: 8,
            uniqueVisitDays: 3,
            activityStamps: [.walk, .cycle],
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_100_000),
            weeklyCharge: 2,
            regionIDs: ["stub"]
        )

        let record = PersistedTileRecord(from: original)
        let restored = record.asWorldTile()

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.coordinate, original.coordinate)
        XCTAssertEqual(restored.state, original.state)
        XCTAssertEqual(restored.masteryXP, original.masteryXP)
        XCTAssertEqual(restored.visitCount, original.visitCount)
        XCTAssertEqual(restored.activityStamps, original.activityStamps)
    }

    func testWorldSaveFileEncodesWithoutGeometryKeys() throws {
        let tile = WorldTile(
            id: "hex:20:1:1",
            coordinate: TileCoordinate(q: 1, r: 1),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let save = WorldSaveFile(
            tiles: [PersistedTileRecord(from: tile)],
            progress: PersistedProgressRecord(
                discoveryXPTotal: 100,
                familiarityXPTotal: 0,
                activitiesCompleted: 1
            ),
            frontier: PersistedFrontierRecord(from: .empty)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(save)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let tiles = try XCTUnwrap(object?["tiles"] as? [[String: Any]])
        let keys = Set(tiles[0].keys)

        let allowed: Set<String> = [
            "id", "q", "r", "stateRaw", "masteryXP", "visitCount", "uniqueVisitDays",
            "activityStampsRaw", "firstVisitedAt", "lastVisitedAt", "weeklyCharge",
            "regionIDs",
        ]
        XCTAssertEqual(keys.subtracting(allowed), [], "unexpected persisted tile keys")

        let forbiddenGeometryKeys: Set<String> = [
            "polygon", "vertices", "latitude", "longitude", "lat", "lon",
            "coordinate2D", "geometry", "points",
        ]
        XCTAssertTrue(keys.isDisjoint(with: forbiddenGeometryKeys), "geometry keys must not be persisted")
        XCTAssertTrue(keys.contains("id"))
        XCTAssertTrue(keys.contains("q"))
        XCTAssertTrue(keys.contains("r"))
    }
}
