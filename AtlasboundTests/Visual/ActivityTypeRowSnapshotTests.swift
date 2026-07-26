import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class ActivityTypeRowSnapshotTests: XCTestCase {
    func testSelectedRowSnapshot() throws {
        let view = rowContainer(
            ActivityTypeRow(type: .cycle, isSelected: true)
        )
        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "ActivityTypeRow-selected",
            size: CGSize(width: 390, height: 120)
        )
    }

    func testUnselectedRowSnapshot() throws {
        let view = rowContainer(
            ActivityTypeRow(type: .walk, isSelected: false)
        )
        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "ActivityTypeRow-unselected",
            size: CGSize(width: 390, height: 120)
        )
    }

    func testSelectedRowRenders() throws {
        let view = rowContainer(
            ActivityTypeRow(type: .cycle, isSelected: true)
        )
        try SnapshotSupport.assertRenders(view, size: CGSize(width: 390, height: 120))
    }

    private func rowContainer<Content: View>(_ content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color.white)
    }
}
