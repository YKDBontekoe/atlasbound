import XCTest
import CoreLocation
import MapKit
@testable import Atlasbound

final class LookAroundLocationPoolTests: XCTestCase {

    func testIsLikelyUrbanRecognizesCityPlacemark() {
        XCTAssertTrue(
            LookAroundLocationPool.isLikelyUrban(
                locality: "London",
                subLocality: nil,
                thoroughfare: nil,
                administrativeArea: "England",
                areasOfInterest: nil
            )
        )
    }

    func testIsLikelyUrbanRecognizesStreetAndRegion() {
        XCTAssertTrue(
            LookAroundLocationPool.isLikelyUrban(
                locality: nil,
                subLocality: nil,
                thoroughfare: "Market St",
                administrativeArea: "California",
                areasOfInterest: nil
            )
        )
    }

    func testIsLikelyUrbanRejectsSparsePlacemark() {
        XCTAssertFalse(
            LookAroundLocationPool.isLikelyUrban(
                locality: nil,
                subLocality: nil,
                thoroughfare: nil,
                administrativeArea: nil,
                areasOfInterest: nil
            )
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
