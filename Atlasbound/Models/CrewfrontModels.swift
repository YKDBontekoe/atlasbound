import Foundation

/// Permanent recipe for a tactical card. Blueprints are never transferable or lost.
struct CardBlueprint: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let discipline: SkillDiscipline?
    let kind: BattleCardKind
    let detail: String
    let energyCost: Int
    let speed: Int
    let power: Int
    let durability: Int
    let craftInputs: [ItemAmount]
    let symbolName: String
}

enum BattleCardKind: String, Codable, Sendable, CaseIterable {
    case construct
    case installation
    case tactic

    var displayName: String { rawValue.capitalized }
}

enum CardIntegrity: Int, Codable, Sendable, CaseIterable {
    case damaged = 1
    case worn = 2
    case ready = 3

    var isUsable: Bool { rawValue > 0 }
}

/// A crafted copy. Only non-protected, ready copies can be staked in a siege.
struct CardInstance: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let blueprintID: String
    var integrity: CardIntegrity
    let isProtected: Bool
    let craftedAt: Date

    var isStakeEligible: Bool { !isProtected && integrity == .ready }
}

struct BattleDeck: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var cardInstanceIDs: [UUID]
    var relicID: UUID?
    var updatedAt: Date
}

enum BattleTeam: String, Codable, Sendable, CaseIterable {
    case dawn
    case dusk
}

enum BattleHex: Int, Codable, Sendable, CaseIterable, Identifiable {
    case center, northEast, southEast, southWest, northWest, east, west
    var id: Int { rawValue }
}

struct BoardPiece: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let cardInstanceID: UUID
    let team: BattleTeam
    var hex: BattleHex
    var remainingDurability: Int
}

struct BattleParticipant: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let team: BattleTeam
    let displayName: String
    var deckID: UUID
    var hand: [UUID]
    var drawPile: [UUID]
    var energy: Int
    var isAI: Bool
}

enum BattleActionKind: String, Codable, Sendable {
    case deploy
    case reinforce
    case pass
}

struct PlannedBattleAction: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let participantID: UUID
    let kind: BattleActionKind
    let cardInstanceID: UUID?
    let targetHex: BattleHex?
    let submittedAt: Date
}

struct BattleEvent: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let round: Int
    let title: String
    let detail: String
    let createdAt: Date
}

struct BattleState: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var round: Int
    var dawnInfluence: Int
    var duskInfluence: Int
    var guardianDurability: Int
    var pieces: [BoardPiece]
    var participants: [BattleParticipant]
    var events: [BattleEvent]
    var winner: BattleTeam?
    let seededTieBreak: Int

    static let maximumRounds = 6
    static let victoryInfluence = 7
}

struct CardState: Codable, Hashable, Sendable {
    static let schemaVersion = 1
    var knownBlueprintIDs: Set<String>
    var instances: [CardInstance]
    var decks: [BattleDeck]
    var activeBattle: BattleState?

    static func empty(now: Date = .now) -> CardState {
        let starters = CrewfrontCatalog.starterBlueprintIDs.enumerated().map { index, id in
            CardInstance(id: UUID(), blueprintID: id, integrity: .ready, isProtected: true,
                         craftedAt: now.addingTimeInterval(Double(index)))
        }
        let deck = BattleDeck(id: UUID(), name: "Field Deck", cardInstanceIDs: starters.map(\.id), relicID: nil, updatedAt: now)
        return CardState(knownBlueprintIDs: Set(CrewfrontCatalog.starterBlueprintIDs), instances: starters, decks: [deck], activeBattle: nil)
    }
}

enum CrewfrontCatalog {
    static let starterBlueprintIDs = [
        "pathfinder_scout", "survey_ward", "cartographer_bridge", "artificer_spark",
        "trail_signal", "fog_screen", "waystone_anchor", "field_repair",
        "compass_charge", "ribbon_snare", "beacon_array", "atlas_pulse"
    ]

    static let blueprints: [CardBlueprint] = [
        make("pathfinder_scout", "Pathfinder Scout", .pathfinding, .construct, "Fast field unit that claims a nearby hex.", 1, 3, 2, 3, ["trail_ribbon": 1], "figure.walk"),
        make("survey_ward", "Survey Ward", .surveying, .installation, "Holds the Beacon with a measured shield.", 2, 1, 3, 4, ["survey_ink": 1, "cobble_chip": 1], "scope"),
        make("cartographer_bridge", "Cartographer Bridge", .cartography, .installation, "Links two controlled hexes through a waystone line.", 2, 2, 2, 3, ["waystone_shard": 1, "copper_wire": 1], "map"),
        make("artificer_spark", "Artificer Spark", .artifice, .tactic, "Disrupt an opposing construct and charge your next installation.", 1, 4, 2, 0, ["amber_resin": 1], "bolt.fill"),
        make("trail_signal", "Trail Signal", nil, .tactic, "Draw a field response and gain one energy next round.", 1, 4, 1, 0, ["compass_filament": 1], "antenna.radiowaves.left.and.right"),
        make("fog_screen", "Fog Screen", nil, .tactic, "Reduce pressure on a friendly hex this round.", 1, 3, 2, 0, ["fog_lint": 2], "cloud.fog"),
        make("waystone_anchor", "Waystone Anchor", nil, .installation, "A durable neutralizer built from a field seam.", 2, 1, 3, 5, ["waystone_shard": 2], "diamond.fill"),
        make("field_repair", "Field Repair", nil, .tactic, "Restore a friendly piece’s resilience.", 1, 3, 2, 0, ["brass_rivet": 1, "moss_scrap": 1], "wrench.and.screwdriver.fill"),
        make("compass_charge", "Compass Charge", .pathfinding, .tactic, "Press forward with a quick influence surge.", 1, 5, 2, 0, ["compass_filament": 1, "trail_ribbon": 1], "location.north.fill"),
        make("ribbon_snare", "Ribbon Snare", .surveying, .tactic, "Slow the fastest opposing response.", 1, 4, 2, 0, ["trail_ribbon": 2], "ribbon.fill"),
        make("beacon_array", "Beacon Array", .cartography, .construct, "A survey rig that reinforces the central Beacon.", 3, 1, 4, 5, ["survey_ink": 2, "copper_wire": 1], "dot.radiowaves.left.and.right"),
        make("atlas_pulse", "Atlas Pulse", .artifice, .construct, "Unstable machine that hits hard before fading.", 3, 3, 5, 2, ["amber_resin": 1, "mechanism": 1], "waveform.path.ecg")
    ]

    static let byID = Dictionary(uniqueKeysWithValues: blueprints.map { ($0.id, $0) })

    private static func make(_ id: String, _ name: String, _ discipline: SkillDiscipline?, _ kind: BattleCardKind, _ detail: String, _ energy: Int, _ speed: Int, _ power: Int, _ durability: Int, _ ingredients: [String: Int], _ symbol: String) -> CardBlueprint {
        CardBlueprint(id: id, name: name, discipline: discipline, kind: kind, detail: detail, energyCost: energy, speed: speed, power: power, durability: durability, craftInputs: ingredients.map { ItemAmount(itemID: $0.key, quantity: $0.value) }.sorted { $0.itemID < $1.itemID }, symbolName: symbol)
    }
}
