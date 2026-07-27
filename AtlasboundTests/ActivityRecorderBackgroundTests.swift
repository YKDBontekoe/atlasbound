import XCTest
@testable import Atlasbound

@MainActor
final class ActivityRecorderBackgroundTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BackgroundRecordingPreference.storageKey)
        super.tearDown()
    }

    func testBackgroundPreferencePersists() {
        let recorder = ActivityRecorder()
        XCTAssertFalse(recorder.prefersBackgroundRecording)

        recorder.setBackgroundRecordingEnabled(true)
        XCTAssertTrue(recorder.prefersBackgroundRecording)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: BackgroundRecordingPreference.storageKey))

        let reloaded = ActivityRecorder()
        XCTAssertTrue(reloaded.prefersBackgroundRecording)

        recorder.setBackgroundRecordingEnabled(false)
        XCTAssertFalse(recorder.prefersBackgroundRecording)
    }
}
