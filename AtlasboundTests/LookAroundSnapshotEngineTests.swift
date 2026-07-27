import XCTest
@testable import Atlasbound

final class LookAroundSnapshotEngineTests: XCTestCase {
    func testDefaultCameraValues() {
        let camera = LookAroundCamera.default
        XCTAssertEqual(camera.heading, 0)
        XCTAssertEqual(camera.pitch, 0)
    }

    func testCameraEquality() {
        XCTAssertEqual(
            LookAroundCamera(heading: 45, pitch: 10),
            LookAroundCamera(heading: 45, pitch: 10)
        )
        XCTAssertNotEqual(
            LookAroundCamera(heading: 45, pitch: 10),
            LookAroundCamera(heading: 90, pitch: 10)
        )
    }
}
