import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class FrontierSnapshotTests: XCTestCase {
    func testIdleExpeditionPanelSnapshot() throws {
        let store = TileStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).json"),
            installationID: "snapshot-install")
        let history = ActivityHistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json"))
        let controller = WorldController(store: store, activityHistory: history)
        controller.refreshFrontierPresentation()

        let view = IdleExpeditionPanel(controller: controller, store: store)
            .frame(width: 390)
            .padding()
        try SnapshotSupport.assertSnapshot(of: view, named: "IdleExpeditionPanel")
    }

    func testActiveFrontierTrackerSnapshot() throws {
        let store = TileStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("snapshot-\(UUID().uuidString).json"),
            installationID: "snapshot-install")
        let history = ActivityHistoryStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("history-\(UUID().uuidString).json"))
        let controller = WorldController(store: store, activityHistory: history)
        controller.refreshFrontierPresentation()
        if let offer = controller.availableExpeditions.first {
            controller.selectExpedition(offer)
        }

        let view = ActiveFrontierTracker(controller: controller)
            .frame(width: 390)
            .padding()
        try SnapshotSupport.assertSnapshot(of: view, named: "ActiveFrontierTracker")
    }

    func testActivitySummaryWithFrontierSnapshot() throws {
        let summary = ActivitySummary(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            distanceMeters: 3_200,
            sampleCount: 140,
            tilesVisited: 22,
            tilesDiscovered: 9,
            discoveryXP: 900,
            familiarityXP: 60,
            activityType: .walk,
            frontierContribution: FrontierSessionContribution(
                tilePoints: 180,
                connectionBonus: 250,
                completionBonus: 500,
                weeklyTotalAfter: 1_240,
                targetTilesDiscovered: 12,
                targetTilesRequired: 12,
                didConnectTarget: true,
                comboPeak: 1.6
            )
        )
        let view = ActivitySummaryView(summary: summary, onDismiss: {})
        try SnapshotSupport.assertSnapshot(of: view, named: "ActivitySummaryFrontier")
    }
}
