import XCTest
@testable import Atlasbound

final class SessionFeedbackTests: XCTestCase {
    func testDiscoveryTitleSingularAndPlural() {
        let one = SessionFeedbackEvent(kind: .discovery(count: 1))
        XCTAssertEqual(one.title, "+1 tile")
        XCTAssertEqual(one.subtitle, "Discovered")

        let many = SessionFeedbackEvent(kind: .discovery(count: 3))
        XCTAssertEqual(many.title, "+3 tiles")
    }

    func testMasteryTitleUsesDisplayName() {
        let event = SessionFeedbackEvent(kind: .mastery(state: .mastered))
        XCTAssertEqual(event.title, TileState.mastered.displayName)
        XCTAssertEqual(event.subtitle, "Mastery up")
    }
}
