import Foundation
import CoreLocation
import Combine

/// Records and filters location samples during an activity.
/// Foreground-first; configured for background updates when authorization allows.
@MainActor
final class ActivityRecorder: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var samples: [LocationSample] = []
    @Published private(set) var lastLocation: CLLocation?
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var startedAt: Date?
    /// When true, GPS updates are ignored and locations come from `ingestSimulatedLocation`.
    @Published private(set) var isSimulationActive = false
    @Published var activityType: ActivityType = .walk {
        didSet {
            guard oldValue != activityType else { return }
            applyCoreLocationActivityType()
        }
    }
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var prefersBackgroundRecording = false

    private let manager = CLLocationManager()
    private var settings: ActivitySettings
    private var lastAcceptedLocation: CLLocation?
    private var pausedAt: Date?
    private var accumulatedPause: TimeInterval = 0

    /// Invoked on the main actor when a new sample is accepted.
    var onSample: ((LocationSample) -> Void)?

    init(settings: ActivitySettings = .default) {
        self.settings = settings
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = settings.minSampleDistance
        applyCoreLocationActivityType()
        manager.pausesLocationUpdatesAutomatically = true
        // Structure for later background use; only active while recording if authorized.
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = true
        prefersBackgroundRecording = UserDefaults.standard.bool(
            forKey: BackgroundRecordingPreference.storageKey
        )
    }

    private func applyCoreLocationActivityType() {
        switch activityType {
        case .walk, .run, .hike:
            manager.activityType = .fitness
        case .cycle, .publicTransport:
            manager.activityType = .otherNavigation
        case .drive:
            manager.activityType = .automotiveNavigation
        case .unknown:
            manager.activityType = .other
        }
    }

    func updateSettings(_ settings: ActivitySettings) {
        self.settings = settings
        manager.distanceFilter = settings.minSampleDistance
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Ask for always later when enabling true background recording.
            break
        default:
            break
        }
    }

    /// Lightweight location updates for the idle map (no tile recording).
    func startMonitoringIfNeeded() {
        requestAuthorization()
        guard !isSimulationActive else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard !isRecording else { return }
        manager.startUpdatingLocation()
    }

    /// Call when ready to opt into background recording (requires Always auth).
    func enableBackgroundRecordingIfAuthorized() {
        setBackgroundRecordingEnabled(true)
        guard manager.authorizationStatus == .authorizedAlways else {
            manager.requestAlwaysAuthorization()
            return
        }
        applyBackgroundRecordingPreference()
    }

    func setBackgroundRecordingEnabled(_ enabled: Bool) {
        prefersBackgroundRecording = enabled
        UserDefaults.standard.set(enabled, forKey: BackgroundRecordingPreference.storageKey)
        applyBackgroundRecordingPreference()
    }

    private func applyBackgroundRecordingPreference() {
        let shouldEnable = prefersBackgroundRecording
            && manager.authorizationStatus == .authorizedAlways
            && isRecording
            && !isSimulationActive
        manager.allowsBackgroundLocationUpdates = shouldEnable
    }

    func start() {
        clearError()
        requestAuthorization()

        let status = manager.authorizationStatus
        let authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        guard authorized || isSimulationActive else {
            lastErrorMessage = "Location permission is required to record an activity."
            return
        }

        samples = []
        distanceMeters = 0
        lastAcceptedLocation = nil
        startedAt = Date()
        isRecording = true
        isPaused = false
        pausedAt = nil
        accumulatedPause = 0

        if isSimulationActive {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            return
        }

        applyBackgroundRecordingPreference()

        manager.startUpdatingLocation()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pausedAt = Date()
        if !isSimulationActive {
            manager.stopUpdatingLocation()
        }
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if let pausedAt {
            accumulatedPause += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        isPaused = false
        if !isSimulationActive {
            manager.startUpdatingLocation()
        }
    }

    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    /// Elapsed active time, excluding pauses.
    var elapsedActive: TimeInterval {
        guard let startedAt else { return 0 }
        let pauseExtra: TimeInterval
        if isPaused, let pausedAt {
            pauseExtra = accumulatedPause + Date().timeIntervalSince(pausedAt)
        } else {
            pauseExtra = accumulatedPause
        }
        return max(0, Date().timeIntervalSince(startedAt) - pauseExtra)
    }

    /// Instantaneous speed in km/h from the latest sample, or average if unavailable.
    var speedKmh: Double {
        if let speed = lastLocation?.speed, speed >= 0 {
            return speed * 3.6
        }
        let elapsed = elapsedActive
        guard elapsed > 1 else { return 0 }
        return (distanceMeters / elapsed) * 3.6
    }

    @discardableResult
    func stop() -> (samples: [LocationSample], distance: Double, startedAt: Date, endedAt: Date)? {
        guard isRecording else { return nil }
        if isPaused, let pausedAt {
            accumulatedPause += Date().timeIntervalSince(pausedAt)
        }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isRecording = false
        isPaused = false
        pausedAt = nil
        let ended = Date()
        let started = startedAt ?? ended
        startedAt = nil
        accumulatedPause = 0
        return (samples, distanceMeters, started, ended)
    }

    // MARK: - Simulation (DEBUG / tests)

    /// Prefer injected locations over Core Location (Simulator D-pad / unit tests).
    func setSimulationActive(_ active: Bool) {
        guard isSimulationActive != active else { return }
        isSimulationActive = active
        if active {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            clearError()
        } else if isRecording, !isPaused {
            manager.startUpdatingLocation()
        } else if !isRecording {
            startMonitoringIfNeeded()
        }
    }

    /// Push a location through the same filter path as GPS. Updates `lastLocation` even when idle.
    func ingestSimulatedLocation(_ location: CLLocation) {
        lastLocation = location
        guard isRecording, !isPaused else { return }
        accept(location)
    }

    // MARK: - Filtering

    private func accept(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= settings.maxHorizontalAccuracy else {
            return
        }

        if let previous = lastAcceptedLocation {
            let delta = location.distance(from: previous)
            guard delta >= settings.minSampleDistance else { return }
            distanceMeters += delta
        }

        lastAcceptedLocation = location
        lastLocation = location
        clearError()

        let sample = LocationSample(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed
        )
        samples.append(sample)
        onSample?(sample)
    }

    func clearError() {
        lastErrorMessage = nil
    }

    nonisolated static func presentableMessage(for error: Error) -> String? {
        guard let locationError = error as? CLError else {
            return "Location updates are temporarily unavailable. We'll keep trying."
        }

        switch locationError.code {
        case .locationUnknown:
            // Core Location reports this transient condition while it seeks a fix.
            return nil
        case .denied:
            return "Location access is off. Enable it in Settings to record an activity."
        case .network:
            return "Couldn't reach location services. We'll keep trying."
        default:
            return "Location updates are temporarily unavailable. We'll keep trying."
        }
    }
}

extension ActivityRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            self.applyBackgroundRecordingPreference()
            if self.isRecording,
               manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard !self.isSimulationActive else { return }
            guard let latest = locations.last else { return }
            self.lastLocation = latest
            guard self.isRecording, !self.isPaused else { return }
            for location in locations {
                self.accept(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastErrorMessage = Self.presentableMessage(for: error)
        }
    }
}
