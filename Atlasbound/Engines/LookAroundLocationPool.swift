import Foundation
import CoreLocation

/// Generates random world locations biased toward cities with Apple Look Around coverage.
/// Single responsibility: target location generation for GeoGuessr rounds.
struct LookAroundLocationPool: Sendable {

    /// Cities / landmarks with known Look Around coverage.
    static let seeds: [CLLocationCoordinate2D] = [
        CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),  // San Francisco
        CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),   // New York
        CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437),  // Los Angeles
        CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),    // London
        CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),     // Paris
        CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),   // Tokyo
        CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),    // Berlin
        CLLocationCoordinate2D(latitude: 41.9028, longitude: 12.4964),    // Rome
        CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038),    // Madrid
        CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),    // Moscow
        CLLocationCoordinate2D(latitude: 43.6532, longitude: -79.3832),   // Toronto
        CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),  // Sydney
        CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),   // Seoul
        CLLocationCoordinate2D(latitude: 47.3769, longitude: 8.5417),     // Zurich
        CLLocationCoordinate2D(latitude: 59.3293, longitude: 18.0686),    // Stockholm
        CLLocationCoordinate2D(latitude: 45.4215, longitude: -75.6972),   // Ottawa
        CLLocationCoordinate2D(latitude: 38.9072, longitude: -77.0369),   // Washington DC
        CLLocationCoordinate2D(latitude: 41.8781, longitude: -87.6298),   // Chicago
        CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901),     // Dordrecht
        CLLocationCoordinate2D(latitude: 52.3676, longitude: 4.9041),     // Amsterdam
        CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),     // Brussels
        CLLocationCoordinate2D(latitude: 53.3498, longitude: -6.2603),    // Dublin
        CLLocationCoordinate2D(latitude: 60.1699, longitude: 24.9384),    // Helsinki
        CLLocationCoordinate2D(latitude: 45.7640, longitude: 4.8357),     // Lyon
        CLLocationCoordinate2D(latitude: 43.2965, longitude: 5.3698),     // Marseille
        CLLocationCoordinate2D(latitude: 25.2048, longitude: 55.2708),    // Dubai
        CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198),    // Singapore
        CLLocationCoordinate2D(latitude: -22.9068, longitude: -43.1729),  // Rio de Janeiro
        CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207),  // Vancouver
        CLLocationCoordinate2D(latitude: 35.6895, longitude: 51.3890),    // Tehran
    ]

    /// Generate round targets, picking distinct seed cities with a small random offset (~3 km).
    static func generateTargets(count: Int = GeoGuessrConstants.roundsPerGame) -> [CLLocationCoordinate2D] {
        var used = Set<Int>()
        var targets: [CLLocationCoordinate2D] = []
        for _ in 0..<count {
            var seedIndex: Int
            repeat {
                seedIndex = Int.random(in: 0..<seeds.count)
            } while used.contains(seedIndex) && used.count < seeds.count
            used.insert(seedIndex)

            let seed = seeds[seedIndex]
            let offsetLat = Double.random(in: -0.03...0.03)
            let offsetLon = Double.random(in: -0.03...0.03)
            targets.append(CLLocationCoordinate2D(
                latitude: max(-85, min(85, seed.latitude + offsetLat)),
                longitude: seed.longitude + offsetLon
            ))
        }
        return targets
    }
}
