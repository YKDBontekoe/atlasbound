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

    @MainActor
    func testRejectsOutOfOrderSamples() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let recorder = ActivityRecorder(now: { start })
        recorder.setSimulationActive(true)
        XCTAssertTrue(recorder.start())

        recorder.ingestSimulatedLocation(
            location(latitude: 52.0, longitude: 5.0, timestamp: start.addingTimeInterval(2))
        )
        recorder.ingestSimulatedLocation(
            location(latitude: 52.01, longitude: 5.01, timestamp: start.addingTimeInterval(1))
        )

        XCTAssertEqual(recorder.samples.count, 1)
        XCTAssertEqual(recorder.distanceMeters, 0, accuracy: 0.001)
    }

    @MainActor
    func testStopReportsActiveDurationExcludingPause() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var current = start
        let recorder = ActivityRecorder(now: { current })
        recorder.setSimulationActive(true)
        XCTAssertTrue(recorder.start())

        current = start.addingTimeInterval(10)
        recorder.pause()
        current = start.addingTimeInterval(30)
        recorder.resume()
        current = start.addingTimeInterval(45)

        let result = recorder.stop()
        XCTAssertEqual(result?.activeDuration ?? -1, 25, accuracy: 0.001)
    }

    private func location(latitude: Double, longitude: Double, timestamp: Date) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 1,
            timestamp: timestamp
        )
    }
}
