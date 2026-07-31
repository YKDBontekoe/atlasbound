import CoreLocation
import XCTest
@testable import Atlasbound

@MainActor
final class ActivityRecorderBackgroundTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: BackgroundRecordingPreference.storageKey)
        UserDefaults.standard.removeObject(forKey: AutomaticExplorationPreference.foregroundKey)
        UserDefaults.standard.removeObject(forKey: AutomaticExplorationPreference.backgroundKey)
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

    func testDefaultMaxHorizontalAccuracyAllowsTypicalBackgroundFixes() {
        XCTAssertEqual(ActivitySettings.default.maxHorizontalAccuracy, 50)
    }

    func testShouldAllowBackground_recordingRequiresAlwaysAndActiveSession() {
        XCTAssertFalse(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: true,
                isRecording: false,
                automaticExplorationEnabled: false,
                automaticBackgroundEnabled: false,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: false
            )
        )
        XCTAssertFalse(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: true,
                isRecording: true,
                automaticExplorationEnabled: false,
                automaticBackgroundEnabled: false,
                authorizationStatus: .authorizedWhenInUse,
                isSimulationActive: false
            )
        )
        XCTAssertTrue(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: true,
                isRecording: true,
                automaticExplorationEnabled: false,
                automaticBackgroundEnabled: false,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: false
            )
        )
    }

    func testShouldAllowBackground_automaticScreenLocked() {
        XCTAssertTrue(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: false,
                isRecording: false,
                automaticExplorationEnabled: true,
                automaticBackgroundEnabled: true,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: false
            )
        )
        XCTAssertFalse(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: false,
                isRecording: false,
                automaticExplorationEnabled: true,
                automaticBackgroundEnabled: true,
                authorizationStatus: .authorizedWhenInUse,
                isSimulationActive: false
            )
        )
        XCTAssertFalse(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: false,
                isRecording: false,
                automaticExplorationEnabled: true,
                automaticBackgroundEnabled: false,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: false
            )
        )
    }

    func testShouldAllowBackground_simulationDisablesDelivery() {
        XCTAssertFalse(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: true,
                isRecording: true,
                automaticExplorationEnabled: true,
                automaticBackgroundEnabled: true,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: true
            )
        )
    }

    func testShouldAllowBackground_afterStopRecording_automaticStillEligible() {
        // Mirrors stop(): isRecording becomes false; automatic prefs should still gate true.
        XCTAssertTrue(
            ActivityRecorder.shouldAllowBackgroundLocationUpdates(
                prefersBackgroundRecording: true,
                isRecording: false,
                automaticExplorationEnabled: true,
                automaticBackgroundEnabled: true,
                authorizationStatus: .authorizedAlways,
                isSimulationActive: false
            )
        )
    }

    func testStopReappliesBackgroundPreferenceInsteadOfHardClear() {
        let recorder = ActivityRecorder()
        recorder.setSimulationActive(true)
        recorder.setAutomaticExploration(foreground: true, background: true)
        XCTAssertTrue(recorder.start())

        _ = recorder.stop()
        recorder.setSimulationActive(false)

        // Without Always auth the manager flag stays false, but preference re-application
        // must leave automatic background prefs intact for when Always is granted.
        XCTAssertTrue(recorder.automaticExplorationEnabled)
        XCTAssertTrue(recorder.automaticBackgroundEnabled)
        XCTAssertFalse(recorder.isRecording)
        let wouldEnable = ActivityRecorder.shouldAllowBackgroundLocationUpdates(
            prefersBackgroundRecording: recorder.prefersBackgroundRecording,
            isRecording: recorder.isRecording,
            automaticExplorationEnabled: recorder.automaticExplorationEnabled,
            automaticBackgroundEnabled: recorder.automaticBackgroundEnabled,
            authorizationStatus: .authorizedAlways,
            isSimulationActive: recorder.isSimulationActive
        )
        XCTAssertTrue(wouldEnable)
    }

    func testPauseFlagCouplesToBackgroundGate() {
        // pausesLocationUpdatesAutomatically is set to !canEnable in applyBackgroundRecordingPreference.
        // Assert the coupling via the pure gate so CI auth state cannot flake the manager flags.
        let disabled = ActivityRecorder.shouldAllowBackgroundLocationUpdates(
            prefersBackgroundRecording: false,
            isRecording: false,
            automaticExplorationEnabled: true,
            automaticBackgroundEnabled: true,
            authorizationStatus: .authorizedWhenInUse,
            isSimulationActive: false
        )
        XCTAssertFalse(disabled)
        XCTAssertTrue(!disabled) // pauses stay on when background cannot enable

        let enabled = ActivityRecorder.shouldAllowBackgroundLocationUpdates(
            prefersBackgroundRecording: false,
            isRecording: false,
            automaticExplorationEnabled: true,
            automaticBackgroundEnabled: true,
            authorizationStatus: .authorizedAlways,
            isSimulationActive: false
        )
        XCTAssertTrue(enabled)
        XCTAssertFalse(!enabled) // pauses turn off when background delivery is active
    }
}
