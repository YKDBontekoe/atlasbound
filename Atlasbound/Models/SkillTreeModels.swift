import Foundation

/// Profession-flavored skill disciplines. Players invest freely across all four.
enum SkillDiscipline: String, Codable, Sendable, CaseIterable, Identifiable {
    case pathfinding
    case surveying
    case cartography
    case artifice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pathfinding: "Pathfinding"
        case .surveying: "Surveying"
        case .cartography: "Cartography"
        case .artifice: "Artifice"
        }
    }

    var detail: String {
        switch self {
        case .pathfinding: "Discovery pace, idle scouts, and frontier tempo."
        case .surveying: "Familiarity XP, mastery thresholds, and survey pulses."
        case .cartography: "Field finds, claim buffs, and rare spark odds."
        case .artifice: "Factory speed and Insight thrift."
        }
    }

    var symbolName: String {
        switch self {
        case .pathfinding: "figure.walk.motion"
        case .surveying: "binoculars.fill"
        case .cartography: "map.fill"
        case .artifice: "gearshape.2.fill"
        }
    }
}

/// Soft effect kinds applied by ranked skill nodes.
enum SkillEffectKind: String, Codable, Sendable {
    case discoveryXP
    case familiarityXP
    case masteryThreshold
    case masteryPulse
    case scoutThroughput
    case scoutDailyCap
    case frontierCombo
    case findChance
    case findQuality
    case claimBuff
    case factorySpeed
    case insightCost
}

struct SkillNodeDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let discipline: SkillDiscipline
    let name: String
    let detail: String
    let symbolName: String
    let effectKind: SkillEffectKind
    /// Peak additive bonus approached asymptotically as ranks climb (e.g. 0.35 = +35%).
    let peakBonus: Double
    /// Node IDs that must have at least one rank before this node can be ranked.
    let prerequisiteIDs: Set<String>
}

enum SkillTreeCatalog {
    static let all: [SkillNodeDefinition] = pathfinding + surveying + cartography + artifice

    static let byID: [String: SkillNodeDefinition] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func nodes(for discipline: SkillDiscipline) -> [SkillNodeDefinition] {
        all.filter { $0.discipline == discipline }
    }

    // MARK: - Pathfinding

    private static let pathfinding: [SkillNodeDefinition] = [
        .init(
            id: "path_first_steps",
            discipline: .pathfinding,
            name: "First Steps",
            detail: "Earn more discovery XP on newly charted hexes.",
            symbolName: "shoeprints.fill",
            effectKind: .discoveryXP,
            peakBonus: 0.35,
            prerequisiteIDs: []
        ),
        .init(
            id: "path_fog_runner",
            discipline: .pathfinding,
            name: "Fog Runner",
            detail: "Hired scouts push fog a little faster.",
            symbolName: "wind",
            effectKind: .scoutThroughput,
            peakBonus: 0.50,
            prerequisiteIDs: ["path_first_steps"]
        ),
        .init(
            id: "path_trail_tempo",
            discipline: .pathfinding,
            name: "Trail Tempo",
            detail: "Frontier combo windows last longer.",
            symbolName: "timer",
            effectKind: .frontierCombo,
            peakBonus: 0.40,
            prerequisiteIDs: ["path_first_steps"]
        ),
        .init(
            id: "path_deep_range",
            discipline: .pathfinding,
            name: "Deep Range",
            detail: "Raise the soft daily AFK discovery ceiling.",
            symbolName: "arrow.up.to.line",
            effectKind: .scoutDailyCap,
            peakBonus: 0.60,
            prerequisiteIDs: ["path_fog_runner"]
        ),
        .init(
            id: "path_wayfarer",
            discipline: .pathfinding,
            name: "Wayfarer",
            detail: "Master pathfinding discovery awards.",
            symbolName: "point.topleft.down.to.point.bottomright.curvepath.fill",
            effectKind: .discoveryXP,
            peakBonus: 0.25,
            prerequisiteIDs: ["path_fog_runner", "path_trail_tempo"]
        ),
    ]

    // MARK: - Surveying

    private static let surveying: [SkillNodeDefinition] = [
        .init(
            id: "survey_careful_eye",
            discipline: .surveying,
            name: "Careful Eye",
            detail: "Revisits award more familiarity XP.",
            symbolName: "eye.fill",
            effectKind: .familiarityXP,
            peakBonus: 0.35,
            prerequisiteIDs: []
        ),
        .init(
            id: "survey_soft_measure",
            discipline: .surveying,
            name: "Soft Measure",
            detail: "Mastery ladder thresholds arrive a little sooner.",
            symbolName: "ruler.fill",
            effectKind: .masteryThreshold,
            peakBonus: 0.20,
            prerequisiteIDs: ["survey_careful_eye"]
        ),
        .init(
            id: "survey_beacon_craft",
            discipline: .surveying,
            name: "Beacon Craft",
            detail: "Survey Beacon pulses hit harder.",
            symbolName: "antenna.radiowaves.left.and.right",
            effectKind: .masteryPulse,
            peakBonus: 0.50,
            prerequisiteIDs: ["survey_careful_eye"]
        ),
        .init(
            id: "survey_legend_climb",
            discipline: .surveying,
            name: "Legend Climb",
            detail: "Deep mastery familiarity gains.",
            symbolName: "star.circle.fill",
            effectKind: .familiarityXP,
            peakBonus: 0.25,
            prerequisiteIDs: ["survey_soft_measure"]
        ),
        .init(
            id: "survey_master_surveyor",
            discipline: .surveying,
            name: "Master Surveyor",
            detail: "Softer legendary thresholds for true surveyors.",
            symbolName: "scope",
            effectKind: .masteryThreshold,
            peakBonus: 0.15,
            prerequisiteIDs: ["survey_soft_measure", "survey_beacon_craft"]
        ),
    ]

    // MARK: - Cartography

    private static let cartography: [SkillNodeDefinition] = [
        .init(
            id: "carto_keen_find",
            discipline: .cartography,
            name: "Keen Find",
            detail: "Field finds turn up more often.",
            symbolName: "sparkle.magnifyingglass",
            effectKind: .findChance,
            peakBonus: 0.40,
            prerequisiteIDs: []
        ),
        .init(
            id: "carto_rare_spark",
            discipline: .cartography,
            name: "Rare Spark",
            detail: "Better odds of uncommon and rare drops.",
            symbolName: "sparkles",
            effectKind: .findQuality,
            peakBonus: 0.45,
            prerequisiteIDs: ["carto_keen_find"]
        ),
        .init(
            id: "carto_claim_bond",
            discipline: .cartography,
            name: "Claim Bond",
            detail: "Home and claim buffs run stronger.",
            symbolName: "house.fill",
            effectKind: .claimBuff,
            peakBonus: 0.35,
            prerequisiteIDs: ["carto_keen_find"]
        ),
        .init(
            id: "carto_sector_sense",
            discipline: .cartography,
            name: "Sector Sense",
            detail: "Claimed ground yields more finds.",
            symbolName: "square.grid.3x3.fill",
            effectKind: .findChance,
            peakBonus: 0.25,
            prerequisiteIDs: ["carto_claim_bond"]
        ),
        .init(
            id: "carto_atlas_eye",
            discipline: .cartography,
            name: "Atlas Eye",
            detail: "Quality finds across the atlas.",
            symbolName: "globe.europe.africa.fill",
            effectKind: .findQuality,
            peakBonus: 0.25,
            prerequisiteIDs: ["carto_rare_spark", "carto_claim_bond"]
        ),
    ]

    // MARK: - Artifice

    private static let artifice: [SkillNodeDefinition] = [
        .init(
            id: "art_workshop_tempo",
            discipline: .artifice,
            name: "Workshop Tempo",
            detail: "Factory recipes and extraction tick faster.",
            symbolName: "hare.fill",
            effectKind: .factorySpeed,
            peakBonus: 0.40,
            prerequisiteIDs: []
        ),
        .init(
            id: "art_insight_thrift",
            discipline: .artifice,
            name: "Insight Thrift",
            detail: "Research costs less Atlas Insight.",
            symbolName: "lightbulb.fill",
            effectKind: .insightCost,
            peakBonus: 0.35,
            prerequisiteIDs: ["art_workshop_tempo"]
        ),
        .init(
            id: "art_extract_flow",
            discipline: .artifice,
            name: "Extract Flow",
            detail: "Deeper factory throughput.",
            symbolName: "arrow.triangle.2.circlepath",
            effectKind: .factorySpeed,
            peakBonus: 0.30,
            prerequisiteIDs: ["art_workshop_tempo"]
        ),
        .init(
            id: "art_research_pace",
            discipline: .artifice,
            name: "Research Pace",
            detail: "Insight thrift for late research.",
            symbolName: "book.fill",
            effectKind: .insightCost,
            peakBonus: 0.25,
            prerequisiteIDs: ["art_insight_thrift"]
        ),
        .init(
            id: "art_grand_machine",
            discipline: .artifice,
            name: "Grand Machine",
            detail: "Master artifice speed across the network.",
            symbolName: "building.2.fill",
            effectKind: .factorySpeed,
            peakBonus: 0.20,
            prerequisiteIDs: ["art_insight_thrift", "art_extract_flow"]
        ),
    ]
}

/// Persisted skill ranks only — never geometry.
struct SkillState: Codable, Sendable, Equatable {
    /// nodeID → current rank (0 omitted).
    var ranks: [String: Int]

    static let empty = SkillState(ranks: [:])

    func rank(of nodeID: String) -> Int {
        max(0, ranks[nodeID] ?? 0)
    }
}

/// Aggregated soft modifiers derived from skill ranks.
struct SkillModifiers: Sendable, Equatable {
    var discoveryXPMultiplier: Double = 1
    var familiarityXPMultiplier: Double = 1
    /// Multiplier on mastery XP thresholds (< 1 softens the ladder).
    var masteryThresholdMultiplier: Double = 1
    var masteryPulseMultiplier: Double = 1
    var scoutThroughputMultiplier: Double = 1
    var scoutDailyCapBonus: Int = 0
    var frontierComboWindowBonus: TimeInterval = 0
    var findChanceBonusPercent: Int = 0
    var findQualityBonusPercent: Int = 0
    var claimBuffMultiplier: Double = 1
    var factorySpeedMultiplier: Double = 1
    var insightCostMultiplier: Double = 1

    static let identity = SkillModifiers()
}

struct SkillRankUpResult: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case ranked(nodeID: String, newRank: Int, cost: Int)
        case denied(String)
    }

    let outcome: Outcome
}

struct SkillTreeSnapshot: Sendable, Equatable {
    let explorerLevel: Int
    let pointsEarned: Int
    let pointsSpent: Int
    let pointsAvailable: Int
    let ranks: [String: Int]
    let modifiers: SkillModifiers

    var disciplineRanks: [SkillDiscipline: Int] {
        Dictionary(uniqueKeysWithValues: SkillDiscipline.allCases.map { discipline in
            let total = SkillTreeCatalog.nodes(for: discipline)
                .reduce(0) { $0 + (ranks[$1.id] ?? 0) }
            return (discipline, total)
        })
    }
}
