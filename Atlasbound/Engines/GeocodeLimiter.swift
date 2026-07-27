import Foundation
import CoreLocation

/// CLGeocoder is rate-limited; serialize requests to avoid silent failures.
actor GeocodeLimiter {
    static let shared = GeocodeLimiter()

    private var lastRequest = Date.distantPast
    private let minimumInterval: TimeInterval = 0.15

    func reverseGeocode(at coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            let delay = minimumInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        lastRequest = Date()

        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            return placemarks.first
        } catch {
            return nil
        }
    }
}
