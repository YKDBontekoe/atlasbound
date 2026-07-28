import Foundation
import CoreLocation

/// Pure scoring math for Pinpoint. Single responsibility: distance, area metrics, and score derivation.
struct PinpointScoring: Sendable {

    /// Geodesic distance in meters between two coordinates.
    static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Flat-top hex area from flat-to-flat width in meters.
    static func hexAreaSquareMeters(tileSizeMeters: Double) -> Double {
        TileEngine.areaSquareMeters(flatToFlatMeters: tileSizeMeters)
    }

    static func unlockedAreaM2(discoveredCount: Int, tileSizeMeters: Double) -> Double {
        TileEngine.areaSquareMeters(tileCount: discoveredCount, flatToFlatMeters: tileSizeMeters)
    }

    static func formatArea(_ squareMeters: Double) -> String {
        let km2 = squareMeters / 1_000_000
        if km2 >= 10 {
            return String(format: "%.1f km²", km2)
        }
        return String(format: "%.2f km²", km2)
    }

    static func homeTurfScaleT(unlockedAreaM2: Double) -> Double {
        min(1.0, sqrt(unlockedAreaM2 / 2_000_000))
    }

    static func homeTurfHalfLife(unlockedAreaM2: Double) -> Double {
        let t = homeTurfScaleT(unlockedAreaM2: unlockedAreaM2)
        return 35_000 + (280_000 - 35_000) * t
    }

    static func homeTurfExactBonus(unlockedAreaM2: Double) -> Int {
        let t = homeTurfScaleT(unlockedAreaM2: unlockedAreaM2)
        return Int(round(200 + (900 - 200) * t))
    }

    static func worldwideScore(distanceMeters: Double, exactTile: Bool) -> Int {
        let base = decayScore(distanceMeters: distanceMeters, halfLifeMeters: 500_000)
        return base + (exactTile ? 500 : 0)
    }

    static func homeTurfScore(distanceMeters: Double, exactTile: Bool, unlockedAreaM2: Double) -> Int {
        let halfLife = homeTurfHalfLife(unlockedAreaM2: unlockedAreaM2)
        let base = decayScore(distanceMeters: distanceMeters, halfLifeMeters: halfLife)
        return base + (exactTile ? homeTurfExactBonus(unlockedAreaM2: unlockedAreaM2) : 0)
    }

    private static func decayScore(distanceMeters: Double, halfLifeMeters: Double) -> Int {
        let maxScore = Double(PinpointConstants.maxScorePerRound)
        let raw = maxScore * pow(0.5, distanceMeters / halfLifeMeters)
        return max(0, Int(round(raw)))
    }

    /// Format distance for display (1 decimal km).
    static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
