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

        store.tileSize = .sixty
        let sixtyTile = WorldTile(
            id: TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 60),
            coordinate: TileCoordinate(q: 0, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
        store.upsert(sixtyTile)
        store.addXP(discovery: 100, familiarity: 0)
        XCTAssertEqual(store.discoveredTiles.count, 1)

        store.tileSize = .hundred
        XCTAssertEqual(store.discoveredTiles.count, 0)
        XCTAssertEqual(store.discoveryXPTotal, 0)

        let hundredTile = WorldTile(
            id: TileEngine.makeTileID(q: 2, r: 1, sizeMeters: 100),
            coordinate: TileCoordinate(q: 2, r: 1),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
        store.upsert(hundredTile)
        XCTAssertEqual(store.discoveredTiles.count, 1)

        store.tileSize = .sixty
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.discoveredTiles.first?.id, sixtyTile.id)
    }

    func testClearCurrentSizeOnly() {
        let store = TileStore(fileURL: tempURL)

        store.tileSize = .sixty
        store.upsert(
            WorldTile(
                id: "hex:60:0:0",
                coordinate: TileCoordinate(q: 0, r: 0),
                state: .discovered,
                masteryXP: 100,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        )
        store.addXP(discovery: 100, familiarity: 0)

        store.tileSize = .eighty
        store.upsert(
            WorldTile(
                id: "hex:80:0:0",
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

        store.tileSize = .sixty
        XCTAssertEqual(store.discoveredTiles.count, 1)
        XCTAssertEqual(store.discoveryXPTotal, 100)
    }

    func testPersistsAcrossReload() {
        do {
            let store = TileStore(fileURL: tempURL)
            store.tileSize = .eighty
            store.upsert(
                WorldTile(
                    id: "hex:80:3:-1",
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
        reloaded.tileSize = .eighty
        XCTAssertEqual(reloaded.discoveredTiles.count, 1)
        XCTAssertEqual(reloaded.discoveredTiles.first?.id, "hex:80:3:-1")
        XCTAssertEqual(reloaded.discoveryXPTotal, 100)
        XCTAssertEqual(reloaded.familiarityXPTotal, 60)
    }
}
