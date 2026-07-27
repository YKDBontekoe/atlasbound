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
        let session = PersistedActivityRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            activityType: .run,
            distanceMeters: 2450,
            duration: 1800,
            tilesDiscovered: 7,
            totalXP: 785,
            tileSizeMeters: 60,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            frontierPoints: 42,
            frontierConnectionBonus: 10,
            frontierCompletionBonus: nil,
            frontierWeeklyTotal: 120
        )
        let view = ActivityHistoryRow(session: session)
            .padding()
            .background(Color(.systemBackground))
        try SnapshotSupport.assertSnapshot(of: view, named: "ActivityHistoryRow")
    }

    func testActivitySessionDetailSnapshot() throws {
        let session = PersistedActivityRecord(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            activityType: .drive,
            distanceMeters: 12_400,
            duration: 900,
            tilesDiscovered: 15,
            totalXP: 1500,
            tileSizeMeters: 100,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_900),
            frontierPoints: 80,
            frontierConnectionBonus: 25,
            frontierCompletionBonus: 50,
            frontierWeeklyTotal: 340
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
}

private extension PersistedActivityRecord {
    init(
        id: UUID,
        activityType: ActivityType,
        distanceMeters: Double,
        duration: TimeInterval,
        tilesDiscovered: Int,
        totalXP: Int,
        tileSizeMeters: Int,
        startedAt: Date,
        endedAt: Date,
        frontierPoints: Int?,
        frontierConnectionBonus: Int?,
        frontierCompletionBonus: Int?,
        frontierWeeklyTotal: Int?
    ) {
        self.id = id
        self.activityType = activityType
        self.distanceMeters = distanceMeters
        self.duration = duration
        self.tilesDiscovered = tilesDiscovered
        self.totalXP = totalXP
        self.tileSizeMeters = tileSizeMeters
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.frontierPoints = frontierPoints
        self.frontierConnectionBonus = frontierConnectionBonus
        self.frontierCompletionBonus = frontierCompletionBonus
        self.frontierWeeklyTotal = frontierWeeklyTotal
    }
}
