import XCTest
@testable import Atlasbound

@MainActor
final class ActivityHistoryStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-activities-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testRecordUpdatesLongestDistance() {
        let store = ActivityHistoryStore(fileURL: tempURL)

        store.record(makeSummary(activity: .cycle, distance: 1200), tileSizeMeters: 80)
        store.record(makeSummary(activity: .cycle, distance: 3500), tileSizeMeters: 80)
        store.record(makeSummary(activity: .walk, distance: 900), tileSizeMeters: 60)

        XCTAssertEqual(store.longestDistance(for: .cycle), 3500, accuracy: 0.01)
        XCTAssertEqual(store.longestDistance(for: .walk), 900, accuracy: 0.01)
        XCTAssertEqual(store.totalDistance(for: .cycle), 4700, accuracy: 0.01)
        XCTAssertEqual(store.sessionCount(for: .cycle), 2)
        XCTAssertEqual(store.sessions.count, 3)
    }

    func testSessionCapEvictsOldest() {
        let store = ActivityHistoryStore(fileURL: tempURL)
        for index in 0..<(ActivityHistoryStore.maxSessions + 5) {
            store.record(
                makeSummary(activity: .walk, distance: Double(index + 1)),
                tileSizeMeters: 60
            )
        }
        XCTAssertEqual(store.sessions.count, ActivityHistoryStore.maxSessions)
        XCTAssertEqual(store.sessions.first?.distanceMeters, 6, accuracy: 0.01)
    }

    func testJSONRoundtrip() {
        let store = ActivityHistoryStore(fileURL: tempURL)
        store.record(makeSummary(activity: .hike, distance: 2400), tileSizeMeters: 80)

        let reloaded = ActivityHistoryStore(fileURL: tempURL)
        XCTAssertEqual(reloaded.sessions.count, 1)
        XCTAssertEqual(reloaded.longestDistance(for: .hike), 2400, accuracy: 0.01)
        XCTAssertEqual(reloaded.sessionCount(for: .hike), 1)
    }

    private func makeSummary(activity: ActivityType, distance: Double) -> ActivitySummary {
        ActivitySummary(
            id: UUID(),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            distanceMeters: distance,
            sampleCount: 12,
            tilesVisited: 4,
            tilesDiscovered: 2,
            discoveryXP: 200,
            familiarityXP: 25,
            activityType: activity
        )
    }
}
