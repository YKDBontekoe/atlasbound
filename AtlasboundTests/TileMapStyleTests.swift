import XCTest
import MapKit
@testable import Atlasbound

final class TileMapStyleTests: XCTestCase {
    func testMasteryFillOpacityStepsUpTheLadder() {
        let opacities = [
            TileState.discovered,
            .explored,
            .surveyed,
            .mastered,
            .legendary
        ].map { $0.mapFillOpacity() }

        for index in 1..<opacities.count {
            XCTAssertGreaterThan(
                opacities[index],
                opacities[index - 1],
                "Mastery ladder fills should grow more solid with rank"
            )
        }
    }

    func testWeeklyChargeBoostsOpacityWithoutWashingOut() {
        let base = TileState.discovered.mapFillOpacity(isFreshDiscovery: false)
        let charged = TileState.discovered.mapFillOpacity(isFreshDiscovery: false, weeklyCharge: 2)
        XCTAssertGreaterThan(charged, base)
        XCTAssertLessThanOrEqual(charged, 0.72)
    }

    func testFreshDiscoveryBoostsEarlyMasteryFills() {
        XCTAssertGreaterThan(
            TileState.discovered.mapFillOpacity(isFreshDiscovery: true),
            TileState.discovered.mapFillOpacity()
        )
        XCTAssertGreaterThan(
            TileState.explored.mapFillOpacity(isFreshDiscovery: true),
            TileState.explored.mapFillOpacity()
        )
    }

    func testInteriorTilesHaveNoStrokeWidth() {
        XCTAssertEqual(
            TileState.discovered.mapStrokeWidth(isFreshDiscovery: false, isPerimeter: false),
            0
        )
        XCTAssertGreaterThan(
            TileState.discovered.mapStrokeWidth(isFreshDiscovery: false, isPerimeter: true),
            0
        )
    }

    func testPerimeterStrokeWidthStepsWithMastery() {
        XCTAssertLessThan(
            TileState.discovered.mapPerimeterStrokeWidth,
            TileState.legendary.mapPerimeterStrokeWidth
        )
        XCTAssertLessThan(
            TileState.explored.mapPerimeterStrokeWidth,
            TileState.mastered.mapPerimeterStrokeWidth
        )
    }

    func testSurveyedAndLegendaryUseDistinctBrandHues() {
        // Brand colors should differ from the shared teal/gold early-ladder hues.
        XCTAssertNotEqual(
            String(describing: TileState.surveyed.mapBrandColor),
            String(describing: TileState.explored.mapBrandColor)
        )
        XCTAssertNotEqual(
            String(describing: TileState.legendary.mapBrandColor),
            String(describing: TileState.mastered.mapBrandColor)
        )
    }

    func testNearLODDualRimOnlyOnExploredPlusPerimeter() {
        let exploredNear = TileMapMaterial.resolve(
            state: .explored,
            isPerimeter: true,
            lod: .near
        )
        XCTAssertTrue(exploredNear.drawsDualRim)
        XCTAssertNotNil(exploredNear.innerStroke)
        XCTAssertGreaterThan(exploredNear.innerStrokeWidth, 0)

        let discoveredNear = TileMapMaterial.resolve(
            state: .discovered,
            isPerimeter: true,
            lod: .near
        )
        XCTAssertFalse(discoveredNear.drawsDualRim)

        let exploredMid = TileMapMaterial.resolve(
            state: .explored,
            isPerimeter: true,
            lod: .mid
        )
        XCTAssertFalse(exploredMid.drawsDualRim)

        let legendaryInterior = TileMapMaterial.resolve(
            state: .legendary,
            isPerimeter: false,
            lod: .near
        )
        XCTAssertFalse(legendaryInterior.drawsDualRim)
    }

    func testFarLODSuppressesInteriorFills() {
        let farInterior = TileMapMaterial.resolve(
            state: .mastered,
            isPerimeter: false,
            lod: .far
        )
        XCTAssertEqual(farInterior.outerStrokeWidth, 0)
        XCTAssertFalse(farInterior.drawsDualRim)
        XCTAssertFalse(MapTileLOD.far.drawsInteriorFills)

        let farPerimeter = TileMapMaterial.resolve(
            state: .mastered,
            isPerimeter: true,
            lod: .far
        )
        XCTAssertGreaterThan(farPerimeter.outerStrokeWidth, 0)
        XCTAssertFalse(farPerimeter.drawsDualRim)
    }

    func testChargeStrengthensPerimeterOuterRim() {
        let base = TileMapMaterial.resolve(
            state: .explored,
            weeklyCharge: 0,
            isPerimeter: true,
            lod: .near
        )
        let charged = TileMapMaterial.resolve(
            state: .explored,
            weeklyCharge: 3,
            isPerimeter: true,
            lod: .near
        )
        XCTAssertGreaterThan(charged.outerStrokeWidth, base.outerStrokeWidth)
    }

    func testFreshInteriorKeepsHairlineWithoutDualRim() {
        let fresh = TileMapMaterial.resolve(
            state: .discovered,
            isFreshDiscovery: true,
            isPerimeter: false,
            lod: .near
        )
        XCTAssertGreaterThan(fresh.outerStrokeWidth, 0)
        XCTAssertFalse(fresh.drawsDualRim)
    }
}

final class MapTileLODTests: XCTestCase {
    func testResolveNearMidFarFromSpan() {
        let nearRegion = MKCoordinateRegion(
            center: .init(latitude: 52.0, longitude: 4.0),
            latitudinalMeters: 900,
            longitudinalMeters: 900
        )
        XCTAssertEqual(MapTileLOD.resolve(for: nearRegion), .near)

        let midRegion = MKCoordinateRegion(
            center: .init(latitude: 52.0, longitude: 4.0),
            latitudinalMeters: 3_000,
            longitudinalMeters: 3_000
        )
        XCTAssertEqual(MapTileLOD.resolve(for: midRegion), .mid)

        let farRegion = MKCoordinateRegion(
            center: .init(latitude: 52.0, longitude: 4.0),
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
        XCTAssertEqual(MapTileLOD.resolve(for: farRegion), .far)
    }

    func testNilRegionDefaultsToNear() {
        XCTAssertEqual(MapTileLOD.resolve(for: nil), .near)
    }

    func testCapsTightenWithDistance() {
        XCTAssertGreaterThan(MapTileLOD.near.polygonCap, MapTileLOD.mid.polygonCap)
        XCTAssertGreaterThan(MapTileLOD.mid.polygonCap, MapTileLOD.far.polygonCap)
        XCTAssertLessThanOrEqual(MapTileLOD.near.polygonCap, AtlasTheme.maxVisiblePolygons)

        XCTAssertEqual(MapTileLOD.far.markerCap, 0)
        XCTAssertGreaterThan(MapTileLOD.near.markerCap, MapTileLOD.mid.markerCap)
        XCTAssertGreaterThan(MapTileLOD.near.fogCap, MapTileLOD.far.fogCap)
    }

    func testDrawPolicyFlags() {
        XCTAssertTrue(MapTileLOD.near.drawsDualRim)
        XCTAssertFalse(MapTileLOD.mid.drawsDualRim)
        XCTAssertFalse(MapTileLOD.far.drawsDualRim)

        XCTAssertTrue(MapTileLOD.near.drawsInteriorFills)
        XCTAssertTrue(MapTileLOD.mid.drawsInteriorFills)
        XCTAssertFalse(MapTileLOD.far.drawsInteriorFills)

        XCTAssertEqual(MapTileLOD.near.minimumMarkerState, .explored)
        XCTAssertEqual(MapTileLOD.mid.minimumMarkerState, .mastered)
        XCTAssertNil(MapTileLOD.far.minimumMarkerState)
    }

    func testSpanMetersUsesLatitudeDelta() {
        let region = MKCoordinateRegion(
            center: .init(latitude: 0, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        let meters = MapTileLOD.spanMeters(for: region)
        XCTAssertEqual(meters, 0.01 * 111_320, accuracy: 1)
    }
}
