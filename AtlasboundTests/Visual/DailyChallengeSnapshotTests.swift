import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class DailyChallengeSnapshotTests: XCTestCase {
    private var snapshot: DailyChallengeSnapshot {
        DailyChallengeSnapshot(
            dayKey: "2026-07-29",
            goals: [
                DailyChallengeGoal(kind: .discover, currentValue: 5, targetValue: 5),
                DailyChallengeGoal(kind: .revisit, currentValue: 1, targetValue: 3),
                DailyChallengeGoal(kind: .route, currentValue: 8, targetValue: 12),
            ]
        )
    }

    private func makeController() -> WorldController {
        let store = TileStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("daily-map-\(UUID().uuidString).json"),
            installationID: "daily-snapshot"
        )
        let history = ActivityHistoryStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("daily-history-\(UUID().uuidString).json")
        )
        return WorldController(store: store, activityHistory: history)
    }

    func testDailyChallengeCardSnapshot() throws {
        let view = VStack(spacing: 0) {
            DailyChallengeProgressCard(snapshot: snapshot)
                .padding(20)
            Spacer(minLength: 0)
        }
        .background(AtlasTheme.canvas)

        try SnapshotSupport.assertSnapshot(of: view, named: "DailyChallengeProgressCard")
    }

    func testDailyChallengeCardRendersAtLargeText() throws {
        let view = VStack(spacing: 0) {
            DailyChallengeProgressCard(snapshot: snapshot)
                .padding(20)
            Spacer(minLength: 0)
        }
        .background(AtlasTheme.canvas)
        .environment(\.sizeCategory, .accessibilityLarge)

        try SnapshotSupport.assertRenders(view, size: CGSize(width: 390, height: 844))
    }

    func testDailyChallengeMapMissionSnapshot() throws {
        let controller = makeController()
        let view = VStack {
            MapMissionsStrip(
                controller: controller,
                store: controller.store,
                dailyChallenge: snapshot,
                onDailyTap: {},
                onExpeditionsTap: {}
            )
            Spacer(minLength: 0)
        }
        .background(AtlasTheme.canvas)

        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "DailyChallengeMapMission",
            size: CGSize(width: 390, height: 150)
        )
    }
}
