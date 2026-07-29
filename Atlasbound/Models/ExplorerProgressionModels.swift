import Foundation

struct ExplorerProgressionSnapshot: Sendable, Equatable {
    let totalXP: Int
    let level: Int
    let title: String
    let currentLevelXP: Int
    let nextLevelXP: Int
    let progressFraction: Double
    let atlasTokens: Int
    let rewards: [ExplorerLevelReward]
    let achievements: [ExplorerAchievement]

    var xpIntoLevel: Int { max(0, totalXP - currentLevelXP) }
    var xpNeededForLevel: Int { max(0, nextLevelXP - currentLevelXP) }
    var xpToNextLevel: Int { max(0, nextLevelXP - totalXP) }
}

enum ExplorerRewardKind: String, Sendable {
    case atlasTokens
    case title
    case mapStyle
    case mapLayer

    var displayName: String {
        switch self {
        case .atlasTokens: "Atlas Tokens"
        case .title: "Explorer Title"
        case .mapStyle: "Map Style"
        case .mapLayer: "Map Layer"
        }
    }
}

struct ExplorerLevelReward: Identifiable, Sendable, Equatable {
    let level: Int
    let kind: ExplorerRewardKind
    let name: String
    let detail: String
    let symbolName: String

    var id: String { "\(level):\(kind.rawValue):\(name)" }
}

struct ExplorerAchievement: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let detail: String
    let symbolName: String
    let currentValue: Int
    let targetValue: Int
    let tokenReward: Int

    var isUnlocked: Bool { currentValue >= targetValue }
    var progressFraction: Double {
        guard targetValue > 0 else { return 1 }
        return min(1, Double(currentValue) / Double(targetValue))
    }
}

struct ExplorerProgressionMetrics: Sendable, Equatable {
    var totalXP: Int
    var discoveredTiles: Int
    var masteredTiles: Int
    var legendaryTiles: Int
    var totalVisits: Int
    var activeDays: Int
    var activitiesCompleted: Int
    var stampedActivityTypes: Int
    var expeditionsCompleted: Int
}
