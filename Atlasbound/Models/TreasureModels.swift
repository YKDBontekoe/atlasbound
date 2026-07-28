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
        case .direct: "A shorter route with reliable treasure."
        case .detour: "A longer detour with better rare-relic odds."
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
}

