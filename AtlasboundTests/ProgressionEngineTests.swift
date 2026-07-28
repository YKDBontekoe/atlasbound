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
}
