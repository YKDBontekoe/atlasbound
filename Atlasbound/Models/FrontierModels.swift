import Foundation

/// Coarse sector coordinate on the span-9 axial lattice.
struct SectorCoordinate: Hashable, Codable, Sendable, Comparable {
    let q: Int
    let r: Int

    static func < (lhs: SectorCoordinate, rhs: SectorCoordinate) -> Bool {
        if lhs.q != rhs.q { return lhs.q < rhs.q }
        return lhs.r < rhs.r
    }
}

enum ExpeditionDifficulty: String, Codable, Sendable, CaseIterable {
    case scout
    case trailblazer
    case pathfinder

    var displayName: String {
        switch self {
        case .scout: "Scout"
        case .trailblazer: "Trailblazer"
        case .pathfinder: "Pathfinder"
        }
    }

    var sectorDistance: Int {
        switch self {
        case .scout: 1
        case .trailblazer: 2
        case .pathfinder: 3
        }
    }

    var tilesRequired: Int {
        switch self {
        case .scout: 12
        case .trailblazer: 20
        case .pathfinder: 32
        }
    }

    var completionBonus: Int {
        switch self {
        case .scout: 500
        case .trailblazer: 1_000
        case .pathfinder: 2_000
        }
    }

    var iconName: String {
        switch self {
        case .scout: "binoculars.fill"
        case .trailblazer: "figure.hiking"
        case .pathfinder: "map.fill"
        }
    }
}

/// A weekly frontier expedition offer — IDs and sector refs only, no geometry.
struct ExpeditionOffer: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let difficulty: ExpeditionDifficulty
    let targetSectorID: String
    let targetSectorDistance: Int
    let directionIndex: Int
    let tilesRequired: Int
    let completionBonus: Int
}

/// Per-grid frontier state persisted alongside tile progress.
struct FrontierState: Codable, Hashable, Sendable {
    var weekKey: String
    var offers: [ExpeditionOffer]
    var activeOfferID: String?
    var completedOfferIDs: [String]
    var weeklyScore: Int
    var connectionBonusesAwarded: [String]
    var chargedTileIDs: [String]
    var bestWeekScore: Int
    var lifetimeCompletedExpeditions: Int

    static let empty = FrontierState(
        weekKey: "",
        offers: [],
        activeOfferID: nil,
        completedOfferIDs: [],
        weeklyScore: 0,
        connectionBonusesAwarded: [],
        chargedTileIDs: [],
        bestWeekScore: 0,
        lifetimeCompletedExpeditions: 0
    )

    var availableOffers: [ExpeditionOffer] {
        let completed = Set(completedOfferIDs)
        let active = activeOfferID
        return offers.filter { !completed.contains($0.id) && $0.id != active }
    }

    func offer(byID id: String?) -> ExpeditionOffer? {
        guard let id else { return nil }
        return offers.first { $0.id == id }
    }

    var activeOffer: ExpeditionOffer? {
        offer(byID: activeOfferID)
    }
}

/// Live frontier combo — affects frontier tile points only.
struct FrontierComboState: Sendable, Equatable {
    var count: Int
    var expiresAt: Date?

    static let empty = FrontierComboState(count: 0, expiresAt: nil)

    var multiplier: Double {
        guard count > 0, let expiresAt, expiresAt > .now else { return 1.0 }
        return min(2.0, 1.0 + Double(count) * 0.1)
    }

    var isActive: Bool {
        guard count > 0, let expiresAt else { return false }
        return expiresAt > .now
    }
}

/// Result of scoring a single qualifying frontier tile discovery.
struct FrontierTileAward: Sendable, Equatable {
    let tileID: String
    let basePoints: Int
    let sectorBonus: Int
    let comboMultiplier: Double
    let totalPoints: Int
    let connectionBonus: Int?
}

/// Session-level frontier contribution for activity summary.
struct FrontierSessionContribution: Sendable, Equatable {
    var tilePoints: Int
    var connectionBonus: Int
    var completionBonus: Int
    var weeklyTotalAfter: Int
    var targetTilesDiscovered: Int
    var targetTilesRequired: Int
    var didConnectTarget: Bool
    var comboPeak: Double

    var sessionTotal: Int { tilePoints + connectionBonus + completionBonus }

    static let empty = FrontierSessionContribution(
        tilePoints: 0,
        connectionBonus: 0,
        completionBonus: 0,
        weeklyTotalAfter: 0,
        targetTilesDiscovered: 0,
        targetTilesRequired: 0,
        didConnectTarget: false,
        comboPeak: 1.0
    )
}

/// Ephemeral score callout for map animation.
struct FrontierScoreCallout: Identifiable, Sendable, Equatable {
    let id: UUID
    let tileID: String
    let points: Int
    let createdAt: Date
}
