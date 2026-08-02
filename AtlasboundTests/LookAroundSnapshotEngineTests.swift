import CoreLocation
import XCTest
@testable import Atlasbound

final class LookAroundSnapshotEngineTests: XCTestCase {
    func testDefaultProbesIncludeSpawnAndCardinalsOnly() {
        let probes = LookAroundGalleryProbe.defaultProbes
        XCTAssertEqual(probes.count, 5)
        XCTAssertEqual(probes[0], LookAroundGalleryProbe(latitudeOffsetMeters: 0, longitudeOffsetMeters: 0))
        XCTAssertEqual(probes[1], .north)
        XCTAssertEqual(probes[2], .east)
        XCTAssertEqual(probes[3], .south)
        XCTAssertEqual(probes[4], .west)
        XCTAssertFalse(probes.contains(.northEast))
        XCTAssertFalse(probes.contains(.farNorth))
    }

    func testProbeEquality() {
        XCTAssertEqual(
            LookAroundGalleryProbe(latitudeOffsetMeters: 20, longitudeOffsetMeters: 0),
            .north
        )
        XCTAssertNotEqual(
            LookAroundGalleryProbe.north,
            LookAroundGalleryProbe.east
        )
    }

    func testCardinalOffsetsUseStreetScaleDistance() {
        XCTAssertEqual(LookAroundGalleryProbe.north.latitudeOffsetMeters, 20)
        XCTAssertEqual(LookAroundGalleryProbe.east.longitudeOffsetMeters, 20)
        XCTAssertEqual(LookAroundGalleryProbe.south.latitudeOffsetMeters, -20)
        XCTAssertEqual(LookAroundGalleryProbe.west.longitudeOffsetMeters, -20)
        XCTAssertEqual(LookAroundGalleryProbe.farNorth.latitudeOffsetMeters, 40)
        XCTAssertEqual(LookAroundGalleryProbe.farEast.longitudeOffsetMeters, 40)
    }

    func testCoordinateOffsetNorth() {
        let anchor = CLLocationCoordinate2D(latitude: 52.37, longitude: 4.89)
        let north = LookAroundSnapshotEngine.coordinate(
            from: anchor,
            latitudeOffsetMeters: 20,
            longitudeOffsetMeters: 0
        )
        XCTAssertGreaterThan(north.latitude, anchor.latitude)
        XCTAssertEqual(north.longitude, anchor.longitude, accuracy: 0.000_000_1)

        let expectedDelta = 20.0 / 111_320.0
        XCTAssertEqual(north.latitude - anchor.latitude, expectedDelta, accuracy: 0.000_000_1)
    }

    func testCoordinateOffsetEastAccountsForLatitude() {
        let anchor = CLLocationCoordinate2D(latitude: 52.37, longitude: 4.89)
        let east = LookAroundSnapshotEngine.coordinate(
            from: anchor,
            latitudeOffsetMeters: 0,
            longitudeOffsetMeters: 20
        )
        XCTAssertEqual(east.latitude, anchor.latitude, accuracy: 0.000_000_1)
        XCTAssertGreaterThan(east.longitude, anchor.longitude)

        let metersPerDegreeLon = 111_320.0 * cos(anchor.latitude * .pi / 180)
        let expectedDelta = 20.0 / metersPerDegreeLon
        XCTAssertEqual(east.longitude - anchor.longitude, expectedDelta, accuracy: 0.000_000_1)
    }

    func testProbeCoordinatesPreserveOrder() {
        let anchor = CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
        let coords = LookAroundSnapshotEngine.probeCoordinates(around: anchor)
        XCTAssertEqual(coords.count, LookAroundGalleryProbe.defaultProbes.count)
        XCTAssertEqual(coords[0].latitude, anchor.latitude, accuracy: 0.000_000_1)
        XCTAssertEqual(coords[0].longitude, anchor.longitude, accuracy: 0.000_000_1)
        XCTAssertGreaterThan(coords[1].latitude, anchor.latitude) // north
        XCTAssertGreaterThan(coords[2].longitude, anchor.longitude) // east
        XCTAssertLessThan(coords[3].latitude, anchor.latitude) // south
        XCTAssertLessThan(coords[4].longitude, anchor.longitude) // west
    }

    func testMaxGalleryImagesCap() {
        XCTAssertEqual(LookAroundSnapshotEngine.maxGalleryImages, 4)
    }

    func testAdditionalProbeBudgetIsBounded() {
        XCTAssertEqual(LookAroundSnapshotEngine.additionalProbeBudget, .milliseconds(2_500))
    }

    func testGallerySnapshotSizePassesThroughWhenUnderPixelBudget() {
        let size = CGSize(width: 300, height: 300)
        let rendered = LookAroundSnapshotEngine.gallerySnapshotSize(for: size, scale: 2)
        XCTAssertEqual(rendered.width, 300, accuracy: 0.001)
        XCTAssertEqual(rendered.height, 300, accuracy: 0.001)
    }

    func testGallerySnapshotSizeAccountsForScreenScale() {
        // 1290×2796 pt would be enormous; even 430×932 @3x exceeds the 1024px budget.
        let size = CGSize(width: 430, height: 932)
        let rendered = LookAroundSnapshotEngine.gallerySnapshotSize(for: size, scale: 3)
        let longestPixels = max(rendered.width, rendered.height) * 3
        XCTAssertLessThanOrEqual(longestPixels, LookAroundSnapshotEngine.maxSnapshotPixelDimension + 1)
        XCTAssertLessThan(rendered.height, size.height)

        let expectedAspect = size.width / size.height
        let renderedAspect = rendered.width / rendered.height
        XCTAssertEqual(renderedAspect, expectedAspect, accuracy: 0.01)
    }
}
