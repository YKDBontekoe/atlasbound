import XCTest
import CoreLocation
@testable import Atlasbound

final class LandmarkQuestEngineTests: XCTestCase {
    private let engine = LandmarkQuestEngine()
    private let tileEngine = TileEngine(option: .twenty)

    func testThemeUsesLandmarkContext() {
        XCTAssertEqual(engine.theme(for: target(category: "Water", name: "Canal Bridge")), .waterside)
        XCTAssertEqual(engine.theme(for: target(category: "Park", name: "Willow Garden")), .greenspace)
        XCTAssertEqual(engine.theme(for: target(category: "Museum", name: "Old Hall")), .heritage)
        XCTAssertEqual(engine.theme(for: target(category: "Landmark", name: "Market Square")), .city)
    }

    func testQuestUsesLiveDistanceWhenPlayerCoordinateIsAvailable() throws {
        let targetAxial = TileCoordinate(q: 24, r: -5)
        let targetID = TileEngine.makeTileID(q: targetAxial.q, r: targetAxial.r, sizeMeters: tileEngine.tileSizeMeters)
        let questTarget = LandmarkTarget(
            id: "quest-target",
            tileID: targetID,
            name: "Canal Bridge",
            category: "Bridge",
            clue: "Follow the water",
            isFallback: false,
            distanceMeters: 9_999
        )

        let quest = try XCTUnwrap(
            engine.makeQuest(
                target: questTarget,
                playerCoordinate: tileEngine.centerCoordinate(for: TileCoordinate(q: 0, r: 0)),
                tileEngine: tileEngine
            )
        )

        XCTAssertEqual(quest.theme, .waterside)
        XCTAssertLessThan(quest.distanceMeters, 1_500)
        XCTAssertGreaterThan(quest.distanceMeters, 100)
    }

    func testQuestFallsBackToTargetDistanceWithoutLocation() throws {
        let quest = try XCTUnwrap(
            engine.makeQuest(target: target(category: "Park", name: "Birch Grove", distance: 2_300), playerCoordinate: nil, tileEngine: tileEngine)
        )
        XCTAssertEqual(quest.distanceMeters, 2_300)
        XCTAssertEqual(quest.distanceLabel, "2.3 km away")
    }

    func testCameraMomentsReserveDramaticZoomForClaims() {
        XCTAssertLessThan(MapCameraMoment.Kind.territoryClaim.zoom, MapCameraMoment.Kind.landmarkQuest.zoom)
        XCTAssertGreaterThan(MapCameraMoment.Kind.territoryClaim.pitch, MapCameraMoment.Kind.landmarkQuest.pitch)
    }

    private func target(category: String, name: String, distance: Double = 700) -> LandmarkTarget {
        LandmarkTarget(
            id: "target:\(category):\(name)",
            tileID: TileEngine.makeTileID(q: 8, r: -2, sizeMeters: tileEngine.tileSizeMeters),
            name: name,
            category: category,
            clue: "Find the route",
            isFallback: false,
            distanceMeters: distance
        )
    }
}
