import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class ActivitySummarySnapshotTests: XCTestCase {
    private var fixtureSummary: ActivitySummary {
        ActivitySummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            distanceMeters: 2_450,
            sampleCount: 120,
            tilesVisited: 18,
            tilesDiscovered: 7,
            discoveryXP: 700,
            familiarityXP: 85,
            activityType: .run
        )
    }

    func testActivitySummaryChromeSnapshot() throws {
        let view = ActivitySummaryView(summary: fixtureSummary, onDismiss: {})
        try SnapshotSupport.assertSnapshot(of: view, named: "ActivitySummaryView")
    }

    func testActivitySummaryThemeColors() throws {
        let view = ActivitySummaryView(summary: fixtureSummary, onDismiss: {})
            .frame(width: 390, height: 700)
        try SnapshotSupport.assertThemePresence(
            of: view,
            expectedColors: [
                (CGPoint(x: 20, y: 20), .atlasCanvas),
            ],
            size: CGSize(width: 390, height: 700)
        )
    }
}
