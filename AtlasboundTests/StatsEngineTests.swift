import XCTest
import CoreLocation
import MapKit
@testable import Atlasbound

final class StatsEngineTests: XCTestCase {
    func testMapRegionContainsCoordinatesAcrossAntimeridian() {
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 179),
            span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 6)
        )

        XCTAssertTrue(region.contains(CLLocationCoordinate2D(latitude: 0, longitude: -179)))
        XCTAssertFalse(region.contains(CLLocationCoordinate2D(latitude: 0, longitude: -170)))
        XCTAssertEqual(MapOverlayCuller.wrappedLongitudeDelta(179, -179), 2)
    }

    func testHexAreaFormula20m() {
        let area = StatsEngine.areaSquareMeters(tileCount: 2, flatToFlatMeters: 20)
        XCTAssertEqual(area, 2 * (sqrt(3) / 2) * 20 * 20, accuracy: 0.01)
    }

    func testTotalUnlockedAreaUsesCanonicalWidth() {
        let summary = StatsEngine.totalUnlockedArea(tiles: [
            makeTile(size: 20, q: 0, r: 0),
            makeTile(size: 20, q: 1, r: 0)
        ])

        XCTAssertEqual(summary.totalTileCount, 2)
        XCTAssertEqual(
            summary.totalAreaSquareMeters,
            StatsEngine.areaSquareMeters(tileCount: 2, flatToFlatMeters: 20),
            accuracy: 0.01
        )
    }

    func testActivityFootprintCountsStamps() {
        var walkTile = makeTile(size: 20, q: 0, r: 0)
        walkTile.activityStamps = [.walk, .run]
        var cycleTile = makeTile(size: 20, q: 1, r: 0)
        cycleTile.activityStamps = [.cycle]

        let footprint = StatsEngine.activityFootprint(tiles: [walkTile, cycleTile])
        let walkCount = footprint.first { $0.activity == .walk }?.tileCount
        let runCount = footprint.first { $0.activity == .run }?.tileCount
        let cycleCount = footprint.first { $0.activity == .cycle }?.tileCount

        XCTAssertEqual(walkCount, 1)
        XCTAssertEqual(runCount, 1)
        XCTAssertEqual(cycleCount, 1)
    }

    func testBoundingRegionAndSpan() {
        let engine = TileEngine(tileSizeMeters: 20)
        let centers = [
            engine.centerCoordinate(for: TileCoordinate(q: 0, r: 0)),
            engine.centerCoordinate(for: TileCoordinate(q: 5, r: 2))
        ]

        XCTAssertNotNil(StatsEngine.boundingRegion(tileCenters: centers))
        XCTAssertGreaterThan(StatsEngine.explorerSpanMeters(centers: centers), 0)
    }

    func testActiveExplorationDays() {
        var tile = makeTile(size: 20, q: 0, r: 0)
        tile.firstVisitedAt = Date(timeIntervalSince1970: 1_700_000_000)
        tile.lastVisitedAt = Date(timeIntervalSince1970: 1_700_086_400)
        XCTAssertEqual(StatsEngine.activeExplorationDays(tiles: [tile]), 2)
    }

    func testDeepMasteryCount() {
        var mastered = makeTile(size: 20, q: 0, r: 0)
        mastered.state = .mastered
        var legendary = makeTile(size: 20, q: 1, r: 0)
        legendary.state = .legendary
        var discovered = makeTile(size: 20, q: 2, r: 0)
        discovered.state = .discovered

        XCTAssertEqual(StatsEngine.deepMasteryCount(tiles: [mastered, legendary, discovered]), 2)
    }

    private func makeTile(size: Int, q: Int, r: Int) -> WorldTile {
        WorldTile(
            id: TileEngine.makeTileID(q: q, r: r, sizeMeters: Double(size)),
            coordinate: TileCoordinate(q: q, r: r),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now
        )
    }
}
