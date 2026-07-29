import XCTest
@testable import Atlasbound

final class DailyChallengeEngineTests: XCTestCase {
    private let engine = DailyChallengeEngine()
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testSnapshotCountsTodayDiscoveryRevisitAndUniqueRouteTiles() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        let tiles = [
            makeTile(q: 0, first: today, last: today),
            makeTile(q: 1, first: today, last: today),
            makeTile(q: 2, first: yesterday, last: today),
            makeTile(q: 3, first: yesterday, last: yesterday),
        ]

        let snapshot = engine.snapshot(tiles: tiles, at: today, calendar: calendar)

        XCTAssertEqual(goal(.discover, in: snapshot)?.currentValue, 2)
        XCTAssertEqual(goal(.revisit, in: snapshot)?.currentValue, 1)
        XCTAssertEqual(goal(.route, in: snapshot)?.currentValue, 3)
        XCTAssertEqual(snapshot.completedGoalCount, 0)
        XCTAssertFalse(snapshot.isComplete)
    }

    func testSnapshotCompletesCircuitAtAllThreeTargets() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        var tiles = (0..<5).map { makeTile(q: $0, first: today, last: today) }
        tiles += (5..<12).map { makeTile(q: $0, first: yesterday, last: today) }

        let snapshot = engine.snapshot(tiles: tiles, at: today, calendar: calendar)

        XCTAssertEqual(snapshot.completedGoalCount, 3)
        XCTAssertTrue(snapshot.isComplete)
        XCTAssertEqual(snapshot.progressFraction, 1)
    }

    func testFutureAndPreviousDayVisitsDoNotCount() {
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86_400)
        let tomorrow = today.addingTimeInterval(86_400)
        let tiles = [
            makeTile(q: 0, first: yesterday, last: yesterday),
            makeTile(q: 1, first: tomorrow, last: tomorrow),
        ]

        let snapshot = engine.snapshot(tiles: tiles, at: today, calendar: calendar)

        XCTAssertTrue(snapshot.goals.allSatisfy { $0.currentValue == 0 })
        XCTAssertEqual(snapshot.progressFraction, 0)
    }

    private func goal(
        _ kind: DailyChallengeKind,
        in snapshot: DailyChallengeSnapshot
    ) -> DailyChallengeGoal? {
        snapshot.goals.first { $0.kind == kind }
    }

    private func makeTile(q: Int, first: Date, last: Date) -> WorldTile {
        WorldTile(
            id: TileEngine.makeTileID(q: q, r: 0, sizeMeters: 20),
            coordinate: TileCoordinate(q: q, r: 0),
            state: .discovered,
            masteryXP: 100,
            visitCount: first == last ? 1 : 2,
            firstVisitedAt: first,
            lastVisitedAt: last
        )
    }
}
