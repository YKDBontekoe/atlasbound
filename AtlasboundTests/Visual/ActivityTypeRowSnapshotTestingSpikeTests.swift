import SnapshotTesting
import SwiftUI
import XCTest
@testable import Atlasbound

/// Spike for Point-Free snapshot testing alongside the custom SnapshotSupport harness.
@MainActor
final class ActivityTypeRowSnapshotTestingSpikeTests: XCTestCase {
    func testSelectedRowPointFreeSnapshot() {
        let view = rowContainer(
            ActivityTypeRow(type: .cycle, isSelected: true)
        )

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: 390, height: 120)),
            record: SnapshotSupport.isRecording
        )
    }

    private func rowContainer<Content: View>(_ content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white)
    }
}
