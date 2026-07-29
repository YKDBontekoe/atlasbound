import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class ExplorerProgressionSnapshotTests: XCTestCase {
    private var snapshot: ExplorerProgressionSnapshot {
        ExplorerProgressionEngine().snapshot(
            metrics: ExplorerProgressionMetrics(
                totalXP: 4_850,
                discoveredTiles: 42,
                masteredTiles: 4,
                legendaryTiles: 1,
                totalVisits: 186,
                activeDays: 12,
                activitiesCompleted: 8,
                stampedActivityTypes: 3,
                expeditionsCompleted: 2
            )
        )
    }

    func testExplorerProgressionChromeSnapshot() throws {
        let view = VStack(spacing: 0) {
            ExplorerProgressionView(snapshot: snapshot)
                .padding(20)
            Spacer(minLength: 0)
        }
        .background(AtlasTheme.canvas)

        try SnapshotSupport.assertSnapshot(of: view, named: "ExplorerProgressionView")
    }

    func testExplorerProgressionRendersAtLargeText() throws {
        let view = VStack(spacing: 0) {
            ExplorerProgressionView(snapshot: snapshot)
                .padding(20)
            Spacer(minLength: 0)
        }
        .background(AtlasTheme.canvas)
        .environment(\.sizeCategory, .accessibilityLarge)

        try SnapshotSupport.assertRenders(view, size: CGSize(width: 390, height: 844))
    }
}
