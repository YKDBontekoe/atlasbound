import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class ActivityHistorySnapshotTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-activities-snapshot-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        tempURL = nil
        super.tearDown()
    }

    func testActivityHistoryRowSnapshot() throws {
        let session = Self.makeRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            activity: .run,
            distanceMeters: 2450,
            duration: 1800,
            tilesDiscovered: 7,
            discoveryXP: 700,
            familiarityXP: 85,
            tileSizeMeters: 60,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            frontier: FrontierSessionContribution(
                tilePoints: 42,
                connectionBonus: 10,
                completionBonus: 0,
                weeklyTotalAfter: 120,
                targetTilesDiscovered: 3,
                targetTilesRequired: 5,
                didConnectTarget: false,
                comboPeak: 1.2
            )
        )
        let view = ActivityHistoryRow(session: session)
            .padding()
            .background(Color(.systemBackground))
        try SnapshotSupport.assertSnapshot(of: view, named: "ActivityHistoryRow")
    }

    func testActivitySessionDetailSnapshot() throws {
        let session = Self.makeRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            activity: .drive,
            distanceMeters: 12_400,
            duration: 900,
            tilesDiscovered: 15,
            discoveryXP: 1500,
            familiarityXP: 0,
            tileSizeMeters: 100,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_900),
            frontier: FrontierSessionContribution(
                tilePoints: 80,
                connectionBonus: 25,
                completionBonus: 50,
                weeklyTotalAfter: 340,
                targetTilesDiscovered: 8,
                targetTilesRequired: 10,
                didConnectTarget: true,
                comboPeak: 1.8
            )
        )
        let view = ActivitySessionDetailView(session: session, onDismiss: {})
        try SnapshotSupport.assertSnapshot(of: view, named: "ActivitySessionDetailView")
    }

    func testActivityHistoryEmptyStateRenders() throws {
        let store = ActivityHistoryStore(fileURL: tempURL)
        let view = NavigationStack {
            ActivityHistoryView(activityHistory: store)
        }
        .frame(width: 390, height: 700)
        try SnapshotSupport.assertRenders(view, size: CGSize(width: 390, height: 700))
    }

    private static func makeRecord(
        id: UUID,
        activity: ActivityType,
        distanceMeters: Double,
        duration: TimeInterval,
        tilesDiscovered: Int,
        discoveryXP: Int,
        familiarityXP: Int,
        tileSizeMeters: Int,
        startedAt: Date,
        endedAt: Date,
        frontier: FrontierSessionContribution?
    ) -> PersistedActivityRecord {
        let summary = ActivitySummary(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            sampleCount: 120,
            tilesVisited: tilesDiscovered + 3,
            tilesDiscovered: tilesDiscovered,
            discoveryXP: discoveryXP,
            familiarityXP: familiarityXP,
            activityType: activity,
            frontierContribution: frontier
        )
        return PersistedActivityRecord(from: summary, tileSizeMeters: tileSizeMeters)
    }
}
