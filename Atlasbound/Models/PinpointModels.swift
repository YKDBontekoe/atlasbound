import Foundation
import CoreLocation

enum PinpointGameMode: String, Sendable, Codable, CaseIterable {
    case worldwide
    case homeTurf

    var displayName: String {
        switch self {
        case .worldwide: "Worldwide"
        case .homeTurf: "Home Turf"
        }
    }

    var subtitle: String {
        switch self {
        case .worldwide: "Random streets wherever Look Around covers"
        case .homeTurf: "Only places you've already discovered — prove you know your atlas"
        }
    }
}

/// A single Pinpoint round: target, guess, tile context, and score.
struct PinpointRound: Sendable, Codable, Identifiable {
    let id: UUID
    let mode: PinpointGameMode
    let target: CLLocationCoordinate2D
    let guess: CLLocationCoordinate2D
    let distanceMeters: Double
    let score: Int
    let roundIndex: Int
    let targetTileID: String
    let guessTileID: String
    let hexDistance: Int
    let hitExactTile: Bool
    let guessInDiscoveredAtlas: Bool
    let familiarityXPAwarded: Int

    enum CodingKeys: String, CodingKey {
        case id, mode, targetLat, targetLon, guessLat, guessLon
        case distanceMeters, score, roundIndex
        case targetTileID, guessTileID, hexDistance
        case hitExactTile, guessInDiscoveredAtlas, familiarityXPAwarded
    }

    init(
        id: UUID = UUID(),
        mode: PinpointGameMode,
        target: CLLocationCoordinate2D,
        guess: CLLocationCoordinate2D,
        roundIndex: Int,
        tileEngine: TileEngine,
        guessInDiscoveredAtlas: Bool,
        unlockedAreaM2: Double
    ) {
        self.id = id
        self.mode = mode
        self.target = target
        self.guess = guess
        self.roundIndex = roundIndex
        self.distanceMeters = PinpointScoring.haversine(from: target, to: guess)

        let targetTileID = tileEngine.tileID(for: target)
        let guessTileID = tileEngine.tileID(for: guess)
        self.targetTileID = targetTileID
        self.guessTileID = guessTileID

        let targetAxial = tileEngine.axialCoordinate(for: target)
        let guessAxial = tileEngine.axialCoordinate(for: guess)
        self.hexDistance = TileEngine.hexDistance(targetAxial, guessAxial)
        self.hitExactTile = targetTileID == guessTileID
        self.guessInDiscoveredAtlas = guessInDiscoveredAtlas

        if guessInDiscoveredAtlas && hexDistance <= 2 {
            switch mode {
            case .worldwide:
                familiarityXPAwarded = hitExactTile ? 25 : 15
            case .homeTurf:
                familiarityXPAwarded = hitExactTile ? 40 : 25
            }
        } else {
            familiarityXPAwarded = 0
        }

        switch mode {
        case .worldwide:
            score = PinpointScoring.worldwideScore(distanceMeters: distanceMeters, exactTile: hitExactTile)
        case .homeTurf:
            score = PinpointScoring.homeTurfScore(
                distanceMeters: distanceMeters,
                exactTile: hitExactTile,
                unlockedAreaM2: unlockedAreaM2
            )
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mode = try c.decode(PinpointGameMode.self, forKey: .mode)
        let tLat = try c.decode(Double.self, forKey: .targetLat)
        let tLon = try c.decode(Double.self, forKey: .targetLon)
        target = CLLocationCoordinate2D(latitude: tLat, longitude: tLon)
        let gLat = try c.decode(Double.self, forKey: .guessLat)
        let gLon = try c.decode(Double.self, forKey: .guessLon)
        guess = CLLocationCoordinate2D(latitude: gLat, longitude: gLon)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        score = try c.decode(Int.self, forKey: .score)
        roundIndex = try c.decode(Int.self, forKey: .roundIndex)
        targetTileID = try c.decode(String.self, forKey: .targetTileID)
        guessTileID = try c.decode(String.self, forKey: .guessTileID)
        hexDistance = try c.decode(Int.self, forKey: .hexDistance)
        hitExactTile = try c.decode(Bool.self, forKey: .hitExactTile)
        guessInDiscoveredAtlas = try c.decode(Bool.self, forKey: .guessInDiscoveredAtlas)
        familiarityXPAwarded = try c.decode(Int.self, forKey: .familiarityXPAwarded)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(mode, forKey: .mode)
        try c.encode(target.latitude, forKey: .targetLat)
        try c.encode(target.longitude, forKey: .targetLon)
        try c.encode(guess.latitude, forKey: .guessLat)
        try c.encode(guess.longitude, forKey: .guessLon)
        try c.encode(distanceMeters, forKey: .distanceMeters)
        try c.encode(score, forKey: .score)
        try c.encode(roundIndex, forKey: .roundIndex)
        try c.encode(targetTileID, forKey: .targetTileID)
        try c.encode(guessTileID, forKey: .guessTileID)
        try c.encode(hexDistance, forKey: .hexDistance)
        try c.encode(hitExactTile, forKey: .hitExactTile)
        try c.encode(guessInDiscoveredAtlas, forKey: .guessInDiscoveredAtlas)
        try c.encode(familiarityXPAwarded, forKey: .familiarityXPAwarded)
    }
}

/// A completed Pinpoint game with all rounds and total score.
struct PinpointGame: Sendable, Codable, Identifiable {
    let id: UUID
    let mode: PinpointGameMode
    let rounds: [PinpointRound]
    let totalScore: Int
    let completedAt: Date
    let unlockedAreaM2AtGameStart: Double
    let totalFamiliarityXPAwarded: Int

    init(
        id: UUID = UUID(),
        mode: PinpointGameMode,
        rounds: [PinpointRound],
        unlockedAreaM2AtGameStart: Double,
        completedAt: Date = Date()
    ) {
        self.id = id
        self.mode = mode
        self.rounds = rounds
        self.totalScore = rounds.reduce(0) { $0 + $1.score }
        self.completedAt = completedAt
        self.unlockedAreaM2AtGameStart = unlockedAreaM2AtGameStart
        self.totalFamiliarityXPAwarded = rounds.reduce(0) { $0 + $1.familiarityXPAwarded }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        mode = try c.decode(PinpointGameMode.self, forKey: .mode)
        rounds = try c.decode([PinpointRound].self, forKey: .rounds)
        totalScore = try c.decode(Int.self, forKey: .totalScore)
        completedAt = try c.decode(Date.self, forKey: .completedAt)
        unlockedAreaM2AtGameStart = try c.decode(Double.self, forKey: .unlockedAreaM2AtGameStart)
        totalFamiliarityXPAwarded = try c.decode(Int.self, forKey: .totalFamiliarityXPAwarded)
    }

    enum CodingKeys: String, CodingKey {
        case id, mode, rounds, totalScore, completedAt, unlockedAreaM2AtGameStart, totalFamiliarityXPAwarded
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(mode, forKey: .mode)
        try c.encode(rounds, forKey: .rounds)
        try c.encode(totalScore, forKey: .totalScore)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(unlockedAreaM2AtGameStart, forKey: .unlockedAreaM2AtGameStart)
        try c.encode(totalFamiliarityXPAwarded, forKey: .totalFamiliarityXPAwarded)
    }
}

enum PinpointAtlasTier: String, Sendable {
    case starter
    case explorer
    case cartographer

    var displayName: String {
        switch self {
        case .starter: "Starter"
        case .explorer: "Explorer"
        case .cartographer: "Cartographer"
        }
    }

    static func tier(for unlockedAreaM2: Double) -> PinpointAtlasTier {
        if unlockedAreaM2 >= 1_000_000 { return .cartographer }
        if unlockedAreaM2 >= 100_000 { return .explorer }
        return .starter
    }
}

/// Game-level constants.
enum PinpointConstants {
    static let roundsPerGame = 5
    static let maxScorePerRound = 5000
    static let maxPossibleScore = roundsPerGame * maxScorePerRound
    static let homeTurfMinTiles = 10
    static let worldwideRoundSeconds = 90
    static let homeTurfRoundSeconds = 60

    static func roundSeconds(for mode: PinpointGameMode) -> Int {
        switch mode {
        case .worldwide: worldwideRoundSeconds
        case .homeTurf: homeTurfRoundSeconds
        }
    }
}
