import Foundation

enum ExplorationMode: String, Codable, Sendable {
    case idle
    case quickExplore
    case trackedActivity
    case automatic

    var isExplicitSession: Bool {
        self == .quickExplore || self == .trackedActivity
    }
}

enum TreasureChoice: String, Codable, Sendable, CaseIterable, Identifiable {
    case direct
    case detour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .direct: "Follow the clear trail"
        case .detour: "Decode the hidden clue"
        }
    }

    var detail: String {
        switch self {
        case .direct: "A clearer route — still rewards farther landmarks."
        case .detour: "A longer frontier detour with better rare-relic odds."
        }
    }
}

enum RelicTheme: String, Codable, Sendable, CaseIterable {
    case nature
    case culture
    case history
    case city

    var displayName: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .nature: "leaf.fill"
        case .culture: "theatermasks.fill"
        case .history: "building.columns.fill"
        case .city: "building.2.fill"
        }
    }
}

enum RelicRarity: Int, Codable, Sendable, CaseIterable, Comparable {
    case common
    case uncommon
    case rare
    case legendary

    static func < (lhs: RelicRarity, rhs: RelicRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .legendary: "Legendary"
        }
    }
}

struct LandmarkTarget: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let tileID: String
    let name: String
    let category: String
    let clue: String
    let isFallback: Bool
    /// Geodesic / hex-approximated meters from the trail or vault spawn anchor.
    let distanceMeters: Double

    var distanceBand: DistanceLootBand {
        DistanceLootEngine.band(meters: distanceMeters)
    }

    init(
        id: String,
        tileID: String,
        name: String,
        category: String,
        clue: String,
        isFallback: Bool,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.tileID = tileID
        self.name = name
        self.category = category
        self.clue = clue
        self.isFallback = isFallback
        self.distanceMeters = max(0, distanceMeters)
    }

    enum CodingKeys: String, CodingKey {
        case id, tileID, name, category, clue, isFallback, distanceMeters
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tileID = try c.decode(String.self, forKey: .tileID)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        clue = try c.decode(String.self, forKey: .clue)
        isFallback = try c.decode(Bool.self, forKey: .isFallback)
        distanceMeters = try c.decodeIfPresent(Double.self, forKey: .distanceMeters) ?? 0
    }
}

struct TreasureStage: Codable, Hashable, Sendable, Identifiable {
    let id: String
    var directTarget: LandmarkTarget
    var detourTarget: LandmarkTarget
    var selectedChoice: TreasureChoice?
    var isCompleted: Bool

    func target(for previousChoice: TreasureChoice?) -> LandmarkTarget {
        previousChoice == .detour ? detourTarget : directTarget
    }
}

struct TreasureTrail: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let dayKey: String
    var stages: [TreasureStage]
    var currentStageIndex: Int
    var isCompleted: Bool
    var freeRerollsRemaining: Int

    var currentStage: TreasureStage? {
        guard stages.indices.contains(currentStageIndex), !isCompleted else { return nil }
        return stages[currentStageIndex]
    }

    var currentTarget: LandmarkTarget? {
        let priorChoice = currentStageIndex > 0 ? stages[currentStageIndex - 1].selectedChoice : nil
        return currentStage?.target(for: priorChoice)
    }
}

struct WeeklyVaultState: Codable, Hashable, Sendable {
    var weekKey: String
    var keys: Int
    var target: LandmarkTarget?
    var isCompleted: Bool

    static let empty = WeeklyVaultState(weekKey: "", keys: 0, target: nil, isCompleted: false)
    var isUnlocked: Bool { keys >= TreasureConstants.keysRequiredForVault && !isCompleted }
}

struct RelicRecord: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let relicID: String
    let name: String
    let theme: RelicTheme
    let rarity: RelicRarity
    let landmarkName: String
    let discoveredAt: Date
    let source: String
}

struct TreasureEncounter: Identifiable, Sendable, Equatable {
    let id: String
    let target: LandmarkTarget
    let stageNumber: Int
    let isVault: Bool
}

struct TreasureReward: Identifiable, Sendable, Equatable {
    let id: UUID
    let relic: RelicRecord
    let familiarityXP: Int
    let grantedVaultKey: Bool
}

enum TreasureConstants {
    static let stagesPerTrail = 3
    static let keysRequiredForVault = 3
    static let trailCompletionXP = 75
    static let vaultCompletionXP = 150
    static let maximumMapTargets = 2

    /// MapKit search box around the player for named landmarks.
    static let landmarkSearchMeters: Double = 12_000
    /// Minimum geodesic distance for a landmark target.
    static let minTargetMeters: Double = 400
    /// Maximum geodesic distance for a landmark target.
    static let maxTargetMeters: Double = 12_000
    /// Hex ring radii (~1–8 km on the 20 m grid) for offline fallback caches.
    static let fallbackRingRadii = [50, 100, 150, 200, 300, 400]
    /// Weekly vault spawn radius (~5 km on the 20 m grid).
    static let vaultRingRadius = 250
}

