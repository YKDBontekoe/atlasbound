import Foundation
import CoreLocation

/// Pure scoring math for GeoGuessr. Single responsibility: distance calculation and score derivation.
struct GeoGuessrScoring: Sendable {

    /// Haversine distance in meters between two coordinates.
    static func haversine(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) +
                 cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return R * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Exponential decay scoring: 5000 max, halves every ~500 km.
    static func computeScore(distanceMeters: Double) -> Int {
        let maxScore = Double(GeoGuessrConstants.maxScorePerRound)
        let halfLifeMeters = 500_000.0
        let raw = maxScore * pow(0.5, distanceMeters / halfLifeMeters)
        return max(0, Int(round(raw)))
    }

    /// Format distance for display.
    static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
