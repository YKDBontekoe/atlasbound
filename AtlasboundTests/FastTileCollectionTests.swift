import XCTest
import CoreLocation
@testable import Atlasbound

final class LiveRouteSimplifierTests: XCTestCase {
    func testDownsampleKeepsEndpointsAndBoundsCount() {
        let coordinates = (0..<100).map { index in
            CLLocationCoordinate2D(latitude: 51.8 + Double(index) * 0.0001, longitude: 4.69)
        }

        let simplified = LiveRouteSimplifier.downsample(coordinates, maxPoints: 20)
        XCTAssertEqual(simplified.count, 20)
        XCTAssertEqual(simplified.first?.latitude ?? 0, coordinates.first?.latitude ?? -1, accuracy: 1e-12)
        XCTAssertEqual(simplified.last?.latitude ?? 0, coordinates.last?.latitude ?? -1, accuracy: 1e-12)
    }

    func testDownsampleLeavesShortRoutesAlone() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 1, longitude: 2),
            CLLocationCoordinate2D(latitude: 3, longitude: 4)
        ]
        XCTAssertEqual(LiveRouteSimplifier.downsample(coordinates, maxPoints: 240).count, 2)
    }
}

@MainActor
final class FastTileCollectionTests: XCTestCase {
    func testAutomaticExplorationDefersDiskWritesUntilFlush() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-fast-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let worldURL = root.appendingPathComponent("world.json")
        let store = TileStore(fileURL: worldURL, installationID: "fast-test")
        let history = ActivityHistoryStore(fileURL: root.appendingPathComponent("activities.json"))
        let recorder = ActivityRecorder()
        let controller = WorldController(
            store: store,
            activityHistory: history,
            regionLookup: RegionLookupStore(fileURL: root.appendingPathComponent("regions.json")),
            treasureStore: TreasureStore(fileURL: root.appendingPathComponent("treasures.json")),
            recorder: recorder
        )

        recorder.setSimulationActive(true)
        controller.setAutomaticExploration(foreground: true, background: false)

        // WorldController bootstrap may write an empty frontier snapshot before defer engages.
        // Clear it so this assertion only covers discovery writes during automatic exploration.
        try? FileManager.default.removeItem(at: worldURL)
        XCTAssertTrue(store.isDeferringPersistence)

        // Highway-scale leaps: hexLine must still fill, but world JSON stays deferred.
        recorder.ingestSimulatedLocation(location(latitude: 51.8133, longitude: 4.6901, speed: 25))
        recorder.ingestSimulatedLocation(location(latitude: 51.8140, longitude: 4.6915, speed: 25))
        recorder.ingestSimulatedLocation(location(latitude: 51.8150, longitude: 4.6930, speed: 25))

        XCTAssertFalse(store.discoveredTiles.isEmpty)
        XCTAssertTrue(store.isDeferringPersistence)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: worldURL.path),
            "Deferred automatic exploration must not flush discoveries to disk yet"
        )

        store.flushToDiskIfNeeded()
        XCTAssertTrue(FileManager.default.fileExists(atPath: worldURL.path))
        XCTAssertEqual(TileStore(fileURL: worldURL).discoveredTiles.count, store.discoveredTiles.count)
    }

    func testLargeSampleGapStillCoversIntermediateHexes() {
        let engine = TileEngine(option: .twenty)
        let start = CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901)
        let end = offset(start, northMeters: 0, eastMeters: 220)
        let covering = engine.tileIDsCoveringRoute([
            LocationSample(coordinate: start, timestamp: .now, horizontalAccuracy: 5, speed: 30),
            LocationSample(coordinate: end, timestamp: .now.addingTimeInterval(8), horizontalAccuracy: 5, speed: 30)
        ])

        // 220 m / ~20 m hex width ⇒ many tiles; point sampling alone would miss most.
        XCTAssertGreaterThan(covering.count, 8)
        XCTAssertEqual(
            Set(covering).count,
            covering.count,
            "Covering route should not emit duplicate IDs"
        )
    }

    func testHighSpeedPassiveSamplesAreThrottled() {
        let recorder = ActivityRecorder()
        recorder.setSimulationActive(true)
        recorder.setAutomaticExploration(foreground: true, background: false)

        var accepted = 0
        recorder.onPassiveSample = { _ in accepted += 1 }

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let origin = CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901)

        recorder.ingestSimulatedLocation(
            location(coordinate: origin, speed: 20, timestamp: start)
        )
        // 18 m at highway speed should be ignored (effective min ≥ 40 m).
        recorder.ingestSimulatedLocation(
            location(coordinate: offset(origin, northMeters: 0, eastMeters: 18), speed: 20, timestamp: start.addingTimeInterval(1))
        )
        recorder.ingestSimulatedLocation(
            location(coordinate: offset(origin, northMeters: 0, eastMeters: 50), speed: 20, timestamp: start.addingTimeInterval(2))
        )

        XCTAssertEqual(accepted, 2)
    }

    func testApplyLiveFrontierScoreSkipsOfferRegeneration() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-frontier-live-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = TileStore(fileURL: url, installationID: "frontier-live")
        store.setDeferPersistence(true)
        let tile = WorldTile(
            id: "hex:20:0:0",
            coordinate: TileCoordinate(q: 0, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: 1,
            firstVisitedAt: .now,
            lastVisitedAt: .now,
            weeklyCharge: 1
        )
        store.applyLiveFrontierScore(
            weeklyScoreDelta: 25,
            connectionBonuses: [],
            chargedTiles: [tile],
            completedOffer: nil
        )

        XCTAssertEqual(store.frontierState.weeklyScore, 25)
        XCTAssertEqual(store.tiles[tile.id]?.weeklyCharge, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func location(latitude: Double, longitude: Double, speed: CLLocationSpeed) -> CLLocation {
        location(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            speed: speed,
            timestamp: .now
        )
    }

    private func location(
        coordinate: CLLocationCoordinate2D,
        speed: CLLocationSpeed,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 90,
            speed: speed,
            timestamp: timestamp
        )
    }

    private func offset(
        _ coordinate: CLLocationCoordinate2D,
        northMeters: Double,
        eastMeters: Double
    ) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0
        let dLat = (northMeters / earth) * (180 / .pi)
        let cosLat = cos(coordinate.latitude * .pi / 180)
        let dLon = cosLat == 0 ? 0 : (eastMeters / (earth * cosLat)) * (180 / .pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }
}
