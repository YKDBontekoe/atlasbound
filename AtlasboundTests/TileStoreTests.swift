import XCTest
@testable import Atlasbound

@MainActor
final class TileStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-test-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "-shm"))
        tempURL = nil
        super.tearDown()
    }

    func testCanonicalAtlasStoresOnlyTwentyMeterTiles() {
        let store = TileStore(fileURL: tempURL)
        let tile = WorldTile(
            id: "hex:20:0:0",
            coordinate: TileCoordinate(q: 0, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
        store.upsert(tile)
        store.addXP(discovery: 100, familiarity: 0)
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.tileSize, .twenty)
        XCTAssertEqual(store.discoveredTiles.first?.id, tile.id)
    }

    func testRejectsNonCanonicalOrMismatchedTiles() {
        let store = TileStore(fileURL: tempURL)
        let date = Date()
        store.upsertMany([
            WorldTile(
                id: "hex:50:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: date,
                lastVisitedAt: date
            ),
            WorldTile(
                id: "hex:20:1:0",
                coordinate: TileCoordinate(q: 2, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: date,
                lastVisitedAt: date
            ),
        ])

        XCTAssertTrue(store.tiles.isEmpty)
        let reloaded = TileStore(fileURL: tempURL)
        XCTAssertTrue(reloaded.tiles.isEmpty)
    }

    func testClearAtlasWipesAllProgress() {
        let store = TileStore(fileURL: tempURL)
        store.upsert(
            WorldTile(
                id: "hex:20:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        store.addXP(discovery: 100, familiarity: 25)

        store.clearAtlas()
        XCTAssertEqual(store.discoveredTiles.count, 0)
        XCTAssertEqual(store.discoveryXPTotal, 0)
        XCTAssertEqual(store.familiarityXPTotal, 0)

        let reloaded = TileStore(fileURL: tempURL)
        XCTAssertTrue(reloaded.tiles.isEmpty)
        XCTAssertEqual(reloaded.discoveryXPTotal, 0)
    }

    func testDeferredPersistenceFlushesOnDemand() {
        let store = TileStore(fileURL: tempURL)
        store.setDeferPersistence(true)
        store.upsert(
            WorldTile(
                id: "hex:20:1:0",
                coordinate: TileCoordinate(q: 1, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        XCTAssertTrue(store.isDeferringPersistence)

        // Deferred path keeps memory authoritative until flush.
        let midReload = TileStore(fileURL: tempURL)
        XCTAssertTrue(midReload.tiles.isEmpty)

        store.flushToDiskIfNeeded()
        let reloaded = TileStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.discoveredTiles.count, 1)
    }

    func testPersistsAcrossReload() {
        do {
            let store = TileStore(fileURL: tempURL)
            store.upsert(
                WorldTile(
                    id: "hex:20:3:-1",
                    coordinate: TileCoordinate(q: 3, r: -1),
                    state: .explored,
                    masteryXP: 160,
                    visitCount: 4,
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            )
            store.addXP(discovery: 100, familiarity: 60)
        }

        let reloaded = TileStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.discoveredTiles.count, 1)
        XCTAssertEqual(reloaded.discoveredTiles.first?.id, "hex:20:3:-1")
        XCTAssertEqual(reloaded.discoveryXPTotal, 100)
        XCTAssertEqual(reloaded.familiarityXPTotal, 60)
    }

    func testIncrementalUpsertDoesNotRequireFullRewrite() {
        let store = TileStore(fileURL: tempURL)
        store.upsert(
            WorldTile(
                id: "hex:20:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        store.upsert(
            WorldTile(
                id: "hex:20:1:0",
                coordinate: TileCoordinate(q: 1, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        XCTAssertEqual(TileStore(fileURL: tempURL).discoveredTiles.count, 2)
    }
}
