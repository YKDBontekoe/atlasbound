import XCTest
import CoreLocation
@testable import Atlasbound

final class ExplorationModeTests: XCTestCase {
    @MainActor
    func testAutomaticExplorationDiscoversWithoutActivityHistory() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.recorder.setSimulationActive(true)

        fixture.controller.setAutomaticExploration(foreground: true, background: false)
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8133, longitude: 4.6901))
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8137, longitude: 4.6906))

        XCTAssertFalse(fixture.store.discoveredTiles.isEmpty)
        XCTAssertTrue(fixture.history.sessions.isEmpty)
        XCTAssertEqual(fixture.store.activitiesCompleted, 0)
        XCTAssertEqual(fixture.controller.explorationMode, .automatic)
        XCTAssertGreaterThan(fixture.store.frontierState.weeklyScore, 0)
        XCTAssertTrue(fixture.store.discoveredTiles.contains { $0.weeklyCharge > 0 })
    }

    @MainActor
    func testQuickExploreDoesNotCreateActivityHistory() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.recorder.setSimulationActive(true)

        fixture.controller.startQuickExplore()
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8133, longitude: 4.6901))
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8137, longitude: 4.6906))
        fixture.controller.stopActivity()

        XCTAssertTrue(fixture.history.sessions.isEmpty)
        XCTAssertEqual(fixture.store.activitiesCompleted, 0)
        XCTAssertFalse(fixture.store.discoveredTiles.isEmpty)
        XCTAssertNil(fixture.controller.lastSummary)
    }

    @MainActor
    func testTrackedActivityUsesCanonicalGridAndCreatesHistory() {
        let fixture = makeFixture()
        defer { fixture.cleanup() }
        fixture.recorder.setSimulationActive(true)

        fixture.controller.setActivityType(.cycle)
        fixture.controller.startActivity()
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8133, longitude: 4.6901))
        fixture.recorder.ingestSimulatedLocation(location(latitude: 51.8137, longitude: 4.6906))
        fixture.controller.stopActivity()

        XCTAssertEqual(fixture.store.tileSize, .twenty)
        XCTAssertEqual(fixture.history.sessions.count, 1)
        XCTAssertEqual(fixture.history.sessions.first?.activityType, .cycle)
        XCTAssertEqual(fixture.store.activitiesCompleted, 1)
    }

    @MainActor
    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-exploration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = TileStore(fileURL: root.appendingPathComponent("world.json"), installationID: "test")
        let history = ActivityHistoryStore(fileURL: root.appendingPathComponent("activities.json"))
        let treasure = TreasureStore(fileURL: root.appendingPathComponent("treasures.json"))
        let recorder = ActivityRecorder()
        let controller = WorldController(
            store: store,
            activityHistory: history,
            regionLookup: RegionLookupStore(fileURL: root.appendingPathComponent("regions.json")),
            treasureStore: treasure,
            recorder: recorder
        )
        return Fixture(
            root: root,
            store: store,
            history: history,
            recorder: recorder,
            controller: controller
        )
    }

    private func location(latitude: Double, longitude: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 1.4,
            timestamp: .now
        )
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let store: TileStore
        let history: ActivityHistoryStore
        let recorder: ActivityRecorder
        let controller: WorldController

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
