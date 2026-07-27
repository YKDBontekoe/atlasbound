import XCTest
import CoreLocation
import MapKit
@testable import Atlasbound

final class LookAroundLocationPoolTests: XCTestCase {

    func testIsLikelyUrbanRecognizesCityPlacemark() {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
            addressDictionary: [
                kCLPlacemarkLocalityKey as String: "London",
                kCLPlacemarkAdministrativeAreaKey as String: "England",
            ]
        )

        XCTAssertTrue(LookAroundLocationPool.isLikelyUrban(placemark))
    }

    func testIsLikelyUrbanRejectsSparsePlacemark() {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            addressDictionary: [
                kCLPlacemarkOceanKey as String: "Atlantic Ocean",
            ]
        )

        XCTAssertFalse(LookAroundLocationPool.isLikelyUrban(placemark))
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
