import XCTest
@testable import Atlasbound

@MainActor
final class TileStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testMultiSizeIsolation() {
        let store = TileStore(fileURL: tempURL)

        store.tileSize = .fifteen
        let fifteenTile = WorldTile(
            id: TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 15),
            coordinate: TileCoordinate(q: 0, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
        store.upsert(fifteenTile)
        store.addXP(discovery: 100, familiarity: 0)
        XCTAssertEqual(store.discoveredTiles.count, 1)

        store.tileSize = .twentyFive
        XCTAssertEqual(store.discoveredTiles.count, 0)
        XCTAssertEqual(store.discoveryXPTotal, 0)

        let twentyFiveTile = WorldTile(
            id: TileEngine.makeTileID(q: 2, r: 1, sizeMeters: 25),
            coordinate: TileCoordinate(q: 2, r: 1),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
        store.upsert(twentyFiveTile)
        XCTAssertEqual(store.discoveredTiles.count, 1)

        store.tileSize = .fifteen
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.discoveredTiles.first?.id, fifteenTile.id)
    }

    func testClearCurrentSizeOnly() {
        let store = TileStore(fileURL: tempURL)

        store.tileSize = .fifteen
        store.upsert(
            WorldTile(
                id: "hex:15:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        store.addXP(discovery: 100, familiarity: 0)

        store.tileSize = .twenty
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

        store.clearCurrentGrid()
        XCTAssertEqual(store.discoveredTiles.count, 0)
        XCTAssertEqual(store.discoveryXPTotal, 0)

        store.tileSize = .fifteen
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.discoveryXPTotal, 100)
    }

    func testDeferredPersistenceFlushesOnDemand() {
        let store = TileStore(fileURL: tempURL)
        store.tileSize = .twenty

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
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))

        store.flushToDiskIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        let reloaded = TileStore(fileURL: tempURL)
        reloaded.tileSize = .twenty
        XCTAssertEqual(reloaded.discoveredTiles.count, 1)
    }

    func testPersistsAcrossReload() {
        do {
            let store = TileStore(fileURL: tempURL)
            store.tileSize = .twenty
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
        reloaded.tileSize = .twenty
        XCTAssertEqual(reloaded.discoveredTiles.count, 1)
        XCTAssertEqual(reloaded.discoveredTiles.first?.id, "hex:20:3:-1")
        XCTAssertEqual(reloaded.discoveryXPTotal, 100)
        XCTAssertEqual(reloaded.familiarityXPTotal, 60)
    }
}
