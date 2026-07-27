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

    func testCoverageRegionsAreNonEmptyAndValid() {
        let regions = LookAroundLocationPool.lookAroundCoverageRegions
        XCTAssertGreaterThanOrEqual(regions.count, 8)
        for region in regions {
            XCTAssertLessThan(region.minLatitude, region.maxLatitude)
            XCTAssertLessThan(region.minLongitude, region.maxLongitude)
            XCTAssertGreaterThan(region.areaWeight, 0)
        }
    }

    func testCoverageRegionContainsItsRandomSamples() {
        for region in LookAroundLocationPool.lookAroundCoverageRegions {
            for _ in 0..<20 {
                let sample = region.randomCoordinate()
                XCTAssertTrue(region.contains(sample))
            }
        }
    }

    func testRandomCoverageProbeLandsInSomeRegion() {
        for _ in 0..<40 {
            let probe = LookAroundLocationPool.randomCoverageProbe()
            let hits = LookAroundLocationPool.lookAroundCoverageRegions.contains { $0.contains(probe) }
            XCTAssertTrue(hits)
        }
    }

    func testDiversityRejectsNearbyAndAcceptsFar() {
        let amsterdam = CLLocationCoordinate2D(latitude: 52.37, longitude: 4.89)
        let nearby = CLLocationCoordinate2D(latitude: 52.40, longitude: 4.92)
        let tokyo = CLLocationCoordinate2D(latitude: 35.66, longitude: 139.70)

        XCTAssertFalse(
            LookAroundLocationPool.isSufficientlyDistant(
                nearby,
                from: [amsterdam],
                minMeters: LookAroundLocationPool.minimumWorldwideSeparationMeters
            )
        )
        XCTAssertTrue(
            LookAroundLocationPool.isSufficientlyDistant(
                tokyo,
                from: [amsterdam],
                minMeters: LookAroundLocationPool.minimumWorldwideSeparationMeters
            )
        )
        XCTAssertTrue(
            LookAroundLocationPool.isSufficientlyDistant(
                tokyo,
                from: [],
                minMeters: LookAroundLocationPool.minimumWorldwideSeparationMeters
            )
        )
    }

    func testWorldwideSubtitleAvoidsAnywhereOnEarthClaim() {
        XCTAssertFalse(PinpointGameMode.worldwide.subtitle.localizedCaseInsensitiveContains("anywhere on Earth"))
        XCTAssertTrue(PinpointGameMode.worldwide.subtitle.localizedCaseInsensitiveContains("Look Around"))
    }
}
