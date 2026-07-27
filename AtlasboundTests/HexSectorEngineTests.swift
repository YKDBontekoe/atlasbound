import XCTest
@testable import Atlasbound

final class HexSectorEngineTests: XCTestCase {
    private let engine = HexSectorEngine()
    private let tileEngine = TileEngine(tileSizeMeters: 80)

    func testSectorIDFormatIncludesSize() {
        let sector = SectorCoordinate(q: 2, r: -1)
        XCTAssertEqual(engine.sectorID(for: sector, sizeMeters: 80), "sector:80:2:-1")
        XCTAssertEqual(engine.sectorID(for: sector, sizeMeters: 60), "sector:60:2:-1")
    }

    func testDeterministicSectorAssignment() {
        let tile = TileCoordinate(q: 19, r: 4)
        let first = engine.sectorCoordinate(for: tile)
        let second = engine.sectorCoordinate(for: tile)
        XCTAssertEqual(first, second)
    }

    func testStableTieBreakPrefersLowerCoordinates() {
        let tile = TileCoordinate(q: 0, r: 0)
        let sector = engine.sectorCoordinate(for: tile)
        XCTAssertLessThanOrEqual(sector.q, 1)
        XCTAssertLessThanOrEqual(sector.r, 1)
    }

    func testBoundaryMembership() {
        let sector = SectorCoordinate(q: 1, r: 0)
        let members = engine.tiles(in: sector)
        let boundary = engine.boundaryTiles(for: sector)
        XCTAssertFalse(members.isEmpty)
        XCTAssertFalse(boundary.isEmpty)
        XCTAssertTrue(boundary.isSubset(of: members))
    }

    func testCompletionPercentTracksDiscoveredIDs() {
        let sector = engine.sectorCoordinate(for: TileCoordinate(q: 9, r: 0))
        let members = engine.tiles(in: sector)
        let discovered = Set(members.prefix(3).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: 80)
        })
        let percent = engine.completionPercent(
            sector: sector,
            discoveredTileIDs: discovered,
            tileEngine: tileEngine
        )
        XCTAssertGreaterThan(percent, 0)
        XCTAssertLessThan(percent, 100)
    }

    func testParseSectorIDRoundTrip() {
        let id = engine.sectorID(for: SectorCoordinate(q: -2, r: 3), sizeMeters: 100)
        let parsed = engine.parseSectorID(id)
        XCTAssertEqual(parsed?.sector, SectorCoordinate(q: -2, r: 3))
        XCTAssertEqual(parsed?.sizeMeters, 100)
    }
}
