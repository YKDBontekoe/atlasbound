import XCTest
@testable import Atlasbound

final class ProgressionEngineTests: XCTestCase {
    private let progression = ProgressionEngine()
    private let engine = TileEngine(tileSizeMeters: 20)
    private let dayOne = Date(timeIntervalSince1970: 1_700_000_000)

    func testDiscoveryAwardsOnce() {
        var tile = WorldTile(id: "hex:20:0:0", coordinate: TileCoordinate(q: 0, r: 0))

        let first = progression.processVisit(tile: &tile, at: dayOne, activity: .walk)
        XCTAssertEqual(first.kind, .discovery)
        XCTAssertEqual(first.xpAwarded, ProgressionEngine.discoveryXP)
        XCTAssertEqual(tile.state, .discovered)
        XCTAssertEqual(tile.visitCount, 1)
        XCTAssertEqual(tile.masteryXP, 100)

        let second = progression.processVisit(tile: &tile, at: dayOne.addingTimeInterval(60), activity: .walk)
        XCTAssertEqual(second.kind, .familiarity)
        XCTAssertEqual(second.xpAwarded, 25)
        XCTAssertEqual(tile.visitCount, 2)
    }

    func testFamiliarityDiminishingReturns() {
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 1), 25)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 2), 20)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 3), 16)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 4), 12)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 5), 10)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 6), 5)
        XCTAssertEqual(progression.familiarityXP(forVisitCount: 20), 5)
    }

    func testMasteryThresholds() {
        var tile = WorldTile(id: "hex:20:1:0", coordinate: TileCoordinate(q: 1, r: 0))
        _ = progression.processVisit(tile: &tile, at: dayOne, activity: .run)
        XCTAssertEqual(tile.state, .discovered)

        // Drive masteryXP through revisits until thresholds trip.
        while tile.masteryXP < 150 {
            _ = progression.processVisit(tile: &tile, at: dayOne.addingTimeInterval(Double(tile.visitCount)), activity: .run)
        }
        XCTAssertGreaterThanOrEqual(tile.state.rawValue, TileState.explored.rawValue)

        while tile.masteryXP < 200 {
            _ = progression.processVisit(tile: &tile, at: dayOne.addingTimeInterval(Double(tile.visitCount)), activity: .run)
        }
        XCTAssertGreaterThanOrEqual(tile.state.rawValue, TileState.surveyed.rawValue)

        while tile.masteryXP < 300 {
            _ = progression.processVisit(tile: &tile, at: dayOne.addingTimeInterval(Double(tile.visitCount)), activity: .run)
        }
        XCTAssertGreaterThanOrEqual(tile.state.rawValue, TileState.mastered.rawValue)

        while tile.masteryXP < 500 {
            _ = progression.processVisit(tile: &tile, at: dayOne.addingTimeInterval(Double(tile.visitCount)), activity: .run)
        }
        XCTAssertEqual(tile.state, .legendary)
    }

    func testProcessVisitsAggregatesSessionProgress() {
        var tiles: [String: WorldTile] = [:]
        let ids = [
            TileEngine.makeTileID(q: 0, r: 0, sizeMeters: 20),
            TileEngine.makeTileID(q: 1, r: 0, sizeMeters: 20),
        ]

        let firstPass = progression.processVisits(
            tileIDs: ids,
            tiles: &tiles,
            tileEngine: engine,
            at: dayOne,
            activity: .cycle
        )
        XCTAssertEqual(firstPass.tilesDiscovered, 2)
        XCTAssertEqual(firstPass.discoveryXP, 200)
        XCTAssertEqual(firstPass.tilesRevisited, 0)

        let secondPass = progression.processVisits(
            tileIDs: [ids[0]],
            tiles: &tiles,
            tileEngine: engine,
            at: dayOne.addingTimeInterval(120),
            activity: .cycle
        )
        XCTAssertEqual(secondPass.tilesDiscovered, 0)
        XCTAssertEqual(secondPass.tilesRevisited, 1)
        XCTAssertEqual(secondPass.familiarityXP, 25)
    }

    func testProcessVisitsSkipsInvalidGridIDs() {
        var tiles: [String: WorldTile] = [:]
        let progress = progression.processVisits(
            tileIDs: ["hex:50:0:0", "malformed"],
            tiles: &tiles,
            tileEngine: engine,
            at: dayOne,
            activity: .walk
        )

        XCTAssertTrue(tiles.isEmpty)
        XCTAssertEqual(progress.tilesVisited, 0)
        XCTAssertEqual(progress.discoveryXP, 0)
    }
}

final class ExplorerProgressionEngineTests: XCTestCase {
    private let engine = ExplorerProgressionEngine()

    func testLevelCurveUsesCumulativeThresholds() {
        XCTAssertEqual(engine.xpRequired(forLevel: 1), 0)
        XCTAssertEqual(engine.xpRequired(forLevel: 2), 1_000)
        XCTAssertEqual(engine.xpRequired(forLevel: 3), 2_500)
        XCTAssertEqual(engine.level(forTotalXP: 999), 1)
        XCTAssertEqual(engine.level(forTotalXP: 1_000), 2)
        XCTAssertEqual(engine.level(forTotalXP: 2_500), 3)
    }

    func testSnapshotCombinesLevelAndAchievementRewards() {
        let snapshot = engine.snapshot(
            metrics: ExplorerProgressionMetrics(
                totalXP: 2_500,
                discoveredTiles: 100,
                masteredTiles: 25,
                legendaryTiles: 5,
                totalVisits: 500,
                activeDays: 30,
                activitiesCompleted: 4,
                stampedActivityTypes: 4,
                expeditionsCompleted: 10
            )
        )

        XCTAssertEqual(snapshot.level, 3)
        XCTAssertEqual(snapshot.title, "Scout")
        XCTAssertTrue(snapshot.achievements.contains(where: \.isUnlocked))
        XCTAssertGreaterThan(snapshot.atlasTokens, 0)
        XCTAssertTrue(snapshot.rewards.contains { $0.level == 2 && $0.kind == .mapLayer })
    }

    func testMapRewardsUnlockAtTheirRequiredLevels() {
        XCTAssertFalse(engine.is3DMapUnlocked(atLevel: 3))
        XCTAssertTrue(engine.is3DMapUnlocked(atLevel: 4))
        XCTAssertTrue(
            engine.snapshot(
                metrics: ExplorerProgressionMetrics(
                    totalXP: engine.xpRequired(forLevel: 4),
                    discoveredTiles: 0,
                    masteredTiles: 0,
                    legendaryTiles: 0,
                    totalVisits: 0,
                    activeDays: 0,
                    activitiesCompleted: 0,
                    stampedActivityTypes: 0,
                    expeditionsCompleted: 0
                )
            )
            .rewards
            .contains { $0.level == 4 && $0.name == "3D Terrain" }
        )
        XCTAssertFalse(
            engine.snapshot(
                metrics: ExplorerProgressionMetrics(
                    totalXP: engine.xpRequired(forLevel: 5),
                    discoveredTiles: 0,
                    masteredTiles: 0,
                    legendaryTiles: 0,
                    totalVisits: 0,
                    activeDays: 0,
                    activitiesCompleted: 0,
                    stampedActivityTypes: 0,
                    expeditionsCompleted: 0
                )
            )
            .rewards
            .contains { $0.name == "Satellite" || $0.name == "Hybrid" }
        )
    }
}
