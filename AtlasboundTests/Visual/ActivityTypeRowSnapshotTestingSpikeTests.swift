import SnapshotTesting
import SwiftUI
import XCTest
@testable import Atlasbound

/// Spike for Point-Free snapshot testing alongside the custom SnapshotSupport harness.
@MainActor
final class ActivityTypeRowSnapshotTestingSpikeTests: XCTestCase {
    func testSelectedRowPointFreeSnapshot() throws {
        let referenceURL = Self.referenceDirectory
            .appendingPathComponent("testSelectedRowPointFreeSnapshot.1.png")

        if !SnapshotSupport.isRecording && !FileManager.default.fileExists(atPath: referenceURL.path) {
            throw XCTSkip(
                "Missing Point-Free snapshot reference. Record with RECORD_SNAPSHOTS=1 and commit PNGs under Visual/__Snapshots__/ActivityTypeRowSnapshotTestingSpikeTests/."
            )
        }

        let view = rowContainer(
            ActivityTypeRow(type: .cycle, isSelected: true)
        )

        assertSnapshot(
            of: view,
            as: .image(layout: .fixed(width: 390, height: 120)),
            record: SnapshotSupport.isRecording
        )
    }

    private static var referenceDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
            .appendingPathComponent("ActivityTypeRowSnapshotTestingSpikeTests", isDirectory: true)
    }

    private func rowContainer<Content: View>(_ content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white)
    }
}
