import XCTest
import CoreLocation
import MapKit
@testable import Atlasbound

final class LookAroundLocationPoolTests: XCTestCase {

    func testSeedsCoverAtLeastOneRoundPerGame() {
        XCTAssertGreaterThanOrEqual(
            LookAroundLocationPool.seeds.count,
            PinpointConstants.roundsPerGame,
            "Need enough seed cities to pick distinct worldwide rounds"
        )
    }

    func testAtlasRegionReturnsNilForEmptyTiles() {
        let engine = TileEngine(tileSizeMeters: 80)
        XCTAssertNil(LookAroundLocationPool.atlasRegion(for: [], engine: engine))
    }

    func testAtlasRegionSpansDiscoveredTiles() {
        let engine = TileEngine(tileSizeMeters: 80)
        let tiles = [
            WorldTile(id: "hex:80:0:0", coordinate: TileCoordinate(q: 0, r: 0)),
            WorldTile(id: "hex:80:1:0", coordinate: TileCoordinate(q: 1, r: 0)),
        ]

        let region = LookAroundLocationPool.atlasRegion(for: tiles, engine: engine)
        XCTAssertNotNil(region)
        XCTAssertGreaterThan(region?.span.latitudeDelta ?? 0, 0)
        XCTAssertGreaterThan(region?.span.longitudeDelta ?? 0, 0)
    }
}
