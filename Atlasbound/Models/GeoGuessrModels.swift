import Foundation
import CoreLocation

/// A single GeoGuessr round: the target location, the player's guess, and the resulting score.
struct GeoGuessrRound: Sendable, Codable, Identifiable {
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
        self.distanceMeters = GeoGuessrScoring.haversine(from: target, to: guess)
        self.score = GeoGuessrScoring.computeScore(distanceMeters: self.distanceMeters)
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
}

/// A completed GeoGuessr game with all rounds and total score.
struct GeoGuessrGame: Sendable, Codable, Identifiable {
    let id: UUID
    let rounds: [GeoGuessrRound]
    let totalScore: Int
    let completedAt: Date

    init(id: UUID = UUID(), rounds: [GeoGuessrRound], completedAt: Date = Date()) {
        self.id = id
        self.rounds = rounds
        self.totalScore = rounds.reduce(0) { $0 + $1.score }
        self.completedAt = completedAt
    }
}

/// Game-level constants.
enum GeoGuessrConstants {
    static let roundsPerGame = 5
    static let maxScorePerRound = 5000
    static let maxPossibleScore = roundsPerGame * maxScorePerRound
}
