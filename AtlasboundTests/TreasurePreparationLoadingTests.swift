import XCTest
import CoreLocation
@testable import Atlasbound

@MainActor
final class TreasurePreparationLoadingTests: XCTestCase {
    func testPrepareTreasureTrailPublishesBusyStateUntilResolverFinishes() async {
        let fixture = makeFixture(
            resolver: DelayedLandmarkResolver(
                delayNanoseconds: 80_000_000,
                targets: Self.sampleTargets(count: TreasureConstants.stagesPerTrail * 2)
            )
        )
        defer { fixture.cleanup() }

        // Keep automatic exploration off so ingesting a fix does not start prep early.
        fixture.controller.setAutomaticExploration(foreground: false, background: false)
        fixture.recorder.setSimulationActive(true)
        fixture.recorder.ingestSimulatedLocation(Self.sampleLocation)

        XCTAssertFalse(fixture.controller.isPreparingTreasureTrail)
        fixture.controller.prepareTreasureTrail()
        XCTAssertTrue(fixture.controller.isPreparingTreasureTrail)

        let deadline = Date().addingTimeInterval(2)
        while fixture.controller.isPreparingTreasureTrail, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTAssertFalse(fixture.controller.isPreparingTreasureTrail)
        XCTAssertNotNil(fixture.treasure.dailyTrail)
        XCTAssertFalse(fixture.treasure.currentTarget?.isFallback ?? true)
    }

    func testRerollCancelsTreasurePreparationBusyState() async {
        let fixture = makeFixture(
            resolver: DelayedLandmarkResolver(
                delayNanoseconds: 500_000_000,
                targets: Self.sampleTargets(count: TreasureConstants.stagesPerTrail * 2)
            )
        )
        defer { fixture.cleanup() }

        fixture.controller.setAutomaticExploration(foreground: false, background: false)
        fixture.recorder.setSimulationActive(true)
        fixture.recorder.ingestSimulatedLocation(Self.sampleLocation)
        fixture.controller.prepareTreasureTrail()
        XCTAssertTrue(fixture.controller.isPreparingTreasureTrail)

        fixture.controller.rerollTreasureTrail()
        XCTAssertFalse(fixture.controller.isPreparingTreasureTrail)
    }

    // MARK: - Helpers

    private func makeFixture(resolver: any LandmarkResolving) -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-treasure-prep-\(UUID().uuidString)", isDirectory: true)
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
            recorder: recorder,
            landmarkResolver: resolver
        )
        return Fixture(root: root, store: store, treasure: treasure, recorder: recorder, controller: controller)
    }

    private static var sampleLocation: CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 1.4,
            timestamp: .now
        )
    }

    private static func sampleTargets(count: Int) -> [LandmarkTarget] {
        (0..<count).map { index in
            LandmarkTarget(
                id: "landmark:hex:20:\(index):0",
                tileID: "hex:20:\(index):0",
                name: "Landmark \(index)",
                category: "Park",
                clue: "Near landmark \(index).",
                isFallback: false
            )
        }
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let store: TileStore
        let treasure: TreasureStore
        let recorder: ActivityRecorder
        let controller: WorldController

        func cleanup() {
            // Cancel any in-flight landmark search before deleting SQLite files.
            controller.rerollTreasureTrail()
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private struct DelayedLandmarkResolver: LandmarkResolving {
    let delayNanoseconds: UInt64
    let targets: [LandmarkTarget]

    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine,
        count: Int
    ) async -> [LandmarkTarget] {
        try? await Task.sleep(nanoseconds: delayNanoseconds)
        return Array(targets.prefix(count))
    }
}
