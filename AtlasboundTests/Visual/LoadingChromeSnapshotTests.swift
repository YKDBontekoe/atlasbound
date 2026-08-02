import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class LoadingChromeSnapshotTests: XCTestCase {
    func testLoadingWorldViewSnapshot() throws {
        try SnapshotSupport.assertSnapshot(
            of: LoadingWorldView(),
            named: "LoadingWorld"
        )
    }

    func testAtlasInlineBusyLabelSnapshot() throws {
        let view = StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                Text("Places visited")
                    .font(.subheadline.weight(.semibold))
                AtlasInlineBusyLabel(text: "Updating places…")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtlasTheme.canvas)

        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "InlineBusyLabel",
            size: CGSize(width: 390, height: 180)
        )
    }

    func testLoadingWorldRendersAtLargeText() throws {
        try SnapshotSupport.assertRenders(
            LoadingWorldView()
                .environment(\.sizeCategory, .accessibilityLarge),
            size: SnapshotSupport.canvasSize
        )
    }
}
