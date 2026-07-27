import Foundation
import CoreLocation

/// Pure scoring and round logic for the GeoGuessr-style guessing mode.
/// Stateless — caller owns round state; this computes results.
struct GeoGuessrEngine: Sendable {

    /// A single round: the target location and the player's guess.
    struct RoundResult: Sendable, Codable, Identifiable {
        let id: UUID
        let target: CLLocationCoordinate2D
        let guess: CLLocationCoordinate2D
        let distanceMeters: Double
        let score: Int
        let roundIndex: Int

        enum CodingKeys: String, CodingKey {
            case id, targetLat, targetLon, guessLat, guessLon, distanceMeters, score, roundIndex
        }

        init(id: UUID = UUID(), target: CLLocationCoordinate2D, guess: CLLocationCoordinate2D, roundIndex: Int) {
            self.id = id
            self.target = target
            self.guess = guess
            self.roundIndex = roundIndex
            self.distanceMeters = Self.haversine(from: target, to: guess)
            self.score = Self.computeScore(distanceMeters: self.distanceMeters)
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            let tLat = try c.decode(Double.self, forKey: .targetLat)
            let tLon = try c.decode(Double.self, forKey: .targetLon)
            target = CLLocationCoordinate2D(latitude: tLat, longitude: tLon)
            let gLat = try c.decode(Double.self, forKey: .guessLat)
            let gLon = try c.decode(Double.self, forKey: .guessLon)
            guess = CLLocationCoordinate2D(latitude: gLat, longitude: gLon)
            distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
            score = try c.decode(Int.self, forKey: .score)
            roundIndex = try c.decode(Int.self, forKey: .roundIndex)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(target.latitude, forKey: .targetLat)
            try c.encode(target.longitude, forKey: .targetLon)
            try c.encode(guess.latitude, forKey: .guessLat)
            try c.encode(guess.longitude, forKey: .guessLon)
            try c.encode(distanceMeters, forKey: .distanceMeters)
            try c.encode(score, forKey: .score)
            try c.encode(roundIndex, forKey: .roundIndex)
        }

        /// Haversine distance in meters.
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

        /// GeoGuessr-style exponential decay: 5000 max, halves every ~500 km.
        static func computeScore(distanceMeters: Double) -> Int {
            let maxScore = 5000.0
            let halfLifeMeters = 500_000.0
            let raw = maxScore * pow(0.5, distanceMeters / halfLifeMeters)
            return max(0, Int(round(raw)))
        }
    }

    /// Completed game with all rounds.
    struct GameResult: Sendable, Codable, Identifiable {
        let id: UUID
        let rounds: [RoundResult]
        let totalScore: Int
        let completedAt: Date

        init(id: UUID = UUID(), rounds: [RoundResult], completedAt: Date = Date()) {
            self.id = id
            self.rounds = rounds
            self.totalScore = rounds.reduce(0) { $0 + $1.score }
            self.completedAt = completedAt
        }
    }

    static let roundsPerGame = 5
    static let maxPossibleScore = roundsPerGame * 5000

    // MARK: - Random location generation

    /// Well-known cities / landmarks that usually have Look Around coverage.
    /// Apple Look Around is limited; we bias toward places with known coverage.
    static let lookAroundSeeds: [CLLocationCoordinate2D] = [
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
        CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901),     // Dordrecht (home)
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

    /// Generate a random coordinate near a seed city (offset by up to ~5 km).
    static func randomLocation() -> CLLocationCoordinate2D {
        let seed = lookAroundSeeds.randomElement()!
        let offsetLat = Double.random(in: -0.04...0.04)
        let offsetLon = Double.random(in: -0.04...0.04)
        return CLLocationCoordinate2D(
            latitude: max(-85, min(85, seed.latitude + offsetLat)),
            longitude: seed.longitude + offsetLon
        )
    }

    /// Generate a full game's worth of target locations.
    static func generateRoundTargets(count: Int = roundsPerGame) -> [CLLocationCoordinate2D] {
        var used = Set<Int>()
        var targets: [CLLocationCoordinate2D] = []
        for _ in 0..<count {
            var seedIndex: Int
            repeat {
                seedIndex = Int.random(in: 0..<lookAroundSeeds.count)
            } while used.contains(seedIndex) && used.count < lookAroundSeeds.count
            used.insert(seedIndex)

            let seed = lookAroundSeeds[seedIndex]
            let offsetLat = Double.random(in: -0.03...0.03)
            let offsetLon = Double.random(in: -0.03...0.03)
            targets.append(CLLocationCoordinate2D(
                latitude: max(-85, min(85, seed.latitude + offsetLat)),
                longitude: seed.longitude + offsetLon
            ))
        }
        return targets
    }

    /// Format distance for display.
    static func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
