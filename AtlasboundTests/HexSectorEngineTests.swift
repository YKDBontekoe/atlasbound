import XCTest
@testable import Atlasbound

final class HexSectorEngineTests: XCTestCase {
    private let engine = HexSectorEngine()
    private let tileEngine = TileEngine(tileSizeMeters: 20)

    func testSectorSpanMatchesNeighborhoodScale() {
        XCTAssertEqual(HexSectorEngine.span, 36)
    }

    func testSectorIDFormatIncludesSize() {
        let sector = SectorCoordinate(q: 2, r: -1)
        XCTAssertEqual(engine.sectorID(for: sector, sizeMeters: 20), "sector:20:2:-1")
        XCTAssertEqual(engine.sectorID(for: sector, sizeMeters: 15), "sector:15:2:-1")
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
        let sector = engine.sectorCoordinate(for: TileCoordinate(q: 36, r: 0))
        let members = engine.tiles(in: sector)
        XCTAssertFalse(members.isEmpty)
        // Span-36 sectors are large; sample enough tiles so rounded percent is > 0.
        let sampleCount = max(3, members.count / 20)
        let discovered = Set(Array(members).prefix(sampleCount).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: 20)
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
        let id = engine.sectorID(for: SectorCoordinate(q: -2, r: 3), sizeMeters: 25)
        let parsed = engine.parseSectorID(id)
        XCTAssertEqual(parsed?.sector, SectorCoordinate(q: -2, r: 3))
        XCTAssertEqual(parsed?.sizeMeters, 25)
    }
}
