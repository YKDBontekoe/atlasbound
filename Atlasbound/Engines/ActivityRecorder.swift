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
    @Published var activityType: ActivityType = .walk
    @Published var lastErrorMessage: String?

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
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = true
        // Structure for later background use; only active while recording if authorized.
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = true
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
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard !isRecording else { return }
        manager.startUpdatingLocation()
    }

    /// Call when ready to opt into background recording (Phase 1+: requires Always auth).
    func enableBackgroundRecordingIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways else {
            manager.requestAlwaysAuthorization()
            return
        }
        manager.allowsBackgroundLocationUpdates = true
    }

    func start() {
        lastErrorMessage = nil
        requestAuthorization()

        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
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

        if status == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        } else {
            manager.allowsBackgroundLocationUpdates = false
        }

        manager.startUpdatingLocation()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        pausedAt = Date()
        manager.stopUpdatingLocation()
    }

    func resume() {
        guard isRecording, isPaused else { return }
        if let pausedAt {
            accumulatedPause += Date().timeIntervalSince(pausedAt)
        }
        pausedAt = nil
        isPaused = false
        manager.startUpdatingLocation()
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

        let sample = LocationSample(
            coordinate: location.coordinate,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy,
            speed: location.speed
        )
        samples.append(sample)
        onSample?(sample)
    }
}

extension ActivityRecorder: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.isRecording,
               manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
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
            self.lastErrorMessage = error.localizedDescription
        }
    }
}
