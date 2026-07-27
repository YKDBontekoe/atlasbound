import XCTest
import CoreLocation
@testable import Atlasbound

final class TileEngineTests: XCTestCase {
    private let engine = TileEngine(tileSizeMeters: 20)

    func testMakeAndParseTileID() {
        let id = TileEngine.makeTileID(q: 12, r: -4, sizeMeters: 20)
        XCTAssertEqual(id, "hex:20:12:-4")

        let parsed = engine.parseTileID(id)
        XCTAssertEqual(parsed?.q, 12)
        XCTAssertEqual(parsed?.r, -4)
    }

    func testParseTileIDRejectsMalformed() {
        XCTAssertNil(engine.parseTileID("hex:20:onlytwo"))
        XCTAssertNil(engine.parseTileID("tile:80:1:2"))
        XCTAssertNil(engine.parseTileID(""))
    }

    func testProjectRoundTripPreservesLatLon() {
        let original = CLLocationCoordinate2D(latitude: 52.0907, longitude: 5.1214)
        let projected = TileEngine.project(original)
        let roundTrip = TileEngine.unproject(x: projected.x, y: projected.y)
        XCTAssertEqual(roundTrip.latitude, original.latitude, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.longitude, original.longitude, accuracy: 1e-9)
    }

    func testTileIDIncludesSizeAndIsStable() {
        let coordinate = CLLocationCoordinate2D(latitude: 52.0907, longitude: 5.1214)
        let first = engine.tileID(for: coordinate)
        let second = engine.tileID(for: coordinate)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.hasPrefix("hex:20:"))
    }

    func testDifferentSizesDoNotCollide() {
        let coordinate = CLLocationCoordinate2D(latitude: 52.0907, longitude: 5.1214)
        let fifteen = TileEngine(tileSizeMeters: 15).tileID(for: coordinate)
        let twentyFive = TileEngine(tileSizeMeters: 25).tileID(for: coordinate)
        XCTAssertNotEqual(fifteen, twentyFive)
        XCTAssertTrue(fifteen.hasPrefix("hex:15:"))
        XCTAssertTrue(twentyFive.hasPrefix("hex:25:"))
    }

    func testHexLineIsContinuous() {
        let start = TileCoordinate(q: 0, r: 0)
        let end = TileCoordinate(q: 4, r: -2)
        let line = TileEngine.hexLine(from: start, to: end)

        XCTAssertEqual(line.first, start)
        XCTAssertEqual(line.last, end)
        XCTAssertEqual(line.count, TileEngine.hexDistance(start, end) + 1)

        for index in 1..<line.count {
            let distance = TileEngine.hexDistance(line[index - 1], line[index])
            XCTAssertLessThanOrEqual(distance, 1, "hexLine must not skip neighbors")
        }
    }

    func testTileIDsCoveringRouteFillsGapsBetweenDistantSamples() {
        let start = CLLocationCoordinate2D(latitude: 52.0907, longitude: 5.1214)
        let startAxial = engine.axialCoordinate(for: start)
        let farAxial = TileCoordinate(q: startAxial.q + 6, r: startAxial.r - 3)
        let end = engine.centerCoordinate(for: farAxial)

        let samples = [
            LocationSample(coordinate: start, timestamp: .now, horizontalAccuracy: 5, speed: 10),
            LocationSample(coordinate: end, timestamp: .now, horizontalAccuracy: 5, speed: 20),
        ]

        let pointOnly = engine.tileIDs(along: samples)
        let covered = engine.tileIDsCoveringRoute(samples)

        XCTAssertEqual(pointOnly.count, 2)
        XCTAssertGreaterThan(covered.count, pointOnly.count)
        XCTAssertEqual(covered.first, pointOnly.first)
        XCTAssertEqual(covered.last, pointOnly.last)
    }

    func testPolygonHasSixVertices() {
        let polygon = engine.polygon(for: TileCoordinate(q: 1, r: -1))
        XCTAssertEqual(polygon.count, 6)
    }

    func testIsolatedTileIsTerritoryPerimeter() {
        let center = TileCoordinate(q: 0, r: 0)
        let id = TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 20)
        XCTAssertTrue(engine.isTerritoryPerimeter(center, discoveredIDs: [id]))
    }

    func testInteriorHexOfClusterIsNotPerimeter() {
        let center = TileCoordinate(q: 0, r: 0)
        var discovered = Set(engine.neighbors(of: center).map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: 20)
        })
        discovered.insert(TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 20))

        XCTAssertFalse(engine.isTerritoryPerimeter(center, discoveredIDs: discovered))
        for neighbor in engine.neighbors(of: center) {
            XCTAssertTrue(
                engine.isTerritoryPerimeter(neighbor, discoveredIDs: discovered),
                "Ring tiles should form the territory silhouette"
            )
        }
    }

    func testTerritoryPerimeterIDsUsesFullDiscoveredSet() {
        let center = TileCoordinate(q: 0, r: 0)
        let ring = engine.neighbors(of: center)
        let tiles = ([center] + ring).map { axial in
            WorldTile(
                id: TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: 20),
                coordinate: axial,
                state: .discovered,
                masteryXP: 10,
                visitCount: 1,
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        }
        let discoveredIDs = Set(tiles.map(\.id))
        // Viewport might only show the center — perimeter must still use the full ID set.
        let visible = tiles.filter { $0.coordinate == center }
        let perimeter = engine.territoryPerimeterIDs(among: visible, discoveredIDs: discoveredIDs)
        XCTAssertTrue(perimeter.isEmpty)
    }
}
