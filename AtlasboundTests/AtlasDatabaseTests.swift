import XCTest
@testable import Atlasbound

@MainActor
final class AtlasDatabaseTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-db-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-shm"))
        tempURL = nil
        super.tearDown()
    }

    func testLegacyJSONWorldImport() throws {
        let docs = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: docs) }

        let tile = WorldTile(
            id: "hex:20:2:2",
            coordinate: TileCoordinate(q: 2, r: 2),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let world = WorldSaveFile(
            tiles: [PersistedTileRecord(from: tile)],
            progress: PersistedProgressRecord(
                discoveryXPTotal: 100,
                familiarityXPTotal: 25,
                activitiesCompleted: 1
            ),
            frontier: PersistedFrontierRecord(from: .empty)
        )
        JSONFileStore.save(world, to: docs.appendingPathComponent("atlasbound-world.json"))

        let dbURL = docs.appendingPathComponent("atlasbound.sqlite")
        let database = AtlasDatabase(fileURL: dbURL, importLegacyJSON: true)
        let loaded = database.loadWorld()
        XCTAssertEqual(loaded.tiles.count, 1)
        XCTAssertEqual(loaded.tiles["hex:20:2:2"]?.masteryXP, 100)
        XCTAssertEqual(loaded.progress.discoveryXPTotal, 100)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: docs.appendingPathComponent("atlasbound-world.json").path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: docs.appendingPathComponent("atlasbound-world.json.bak").path)
        )
    }

    func testTileColumnsExcludeGeometry() {
        let database = AtlasDatabase.makeIsolated(fileURL: tempURL)
        database.upsertTiles([
            WorldTile(
                id: "hex:20:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        ])
        let loaded = database.loadWorld().tiles["hex:20:0:0"]
        XCTAssertEqual(loaded?.coordinate, TileCoordinate(q: 0, r: 0))
        // Geometry remains derived — PersistedTileRecord still has no polygon fields.
        let keys = Set(Mirror(reflecting: PersistedTileRecord(from: loaded!)).children.compactMap(\.label))
        XCTAssertFalse(keys.contains("polygon"))
        XCTAssertFalse(keys.contains("latitude"))
    }
}
