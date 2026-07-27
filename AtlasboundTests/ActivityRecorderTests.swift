import XCTest
import CoreLocation
@testable import Atlasbound

final class ActivityRecorderTests: XCTestCase {

    func testTransientLocationUnknownIsNotShownToThePlayer() {
        XCTAssertNil(ActivityRecorder.presentableMessage(for: CLError(.locationUnknown)))
    }

    func testDeniedLocationGetsActionableMessage() {
        XCTAssertEqual(
            ActivityRecorder.presentableMessage(for: CLError(.denied)),
            "Location access is off. Enable it in Settings to record an activity."
        )
    }
}
