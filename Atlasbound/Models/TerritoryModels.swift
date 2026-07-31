import Foundation

/// Soft territory claim / Home Base rules for the 20 m atlas.
enum TerritoryConstants {
    /// Minimum discovery fraction required before a sector can be claimed.
    static let claimCompletionThreshold = 0.25
    /// Familiarity XP multiplier inside a claimed (non-home) sector.
    static let claimFamiliarityMultiplier = 1.15
    /// Familiarity XP multiplier inside the Home Base sector.
    static let homeFamiliarityMultiplier = 1.25
    /// Flat percent added to field-find roll thresholds in claimed sectors.
    static let claimFindChanceBonusPercent = 4
    /// Flat percent added to field-find roll thresholds in the Home Base sector.
    static let homeFindChanceBonusPercent = 8
    /// Cooldown before Home Base can move to another claimed sector.
    static let homeMoveCooldown: TimeInterval = 24 * 60 * 60
}

/// One claimed neighborhood sector — IDs only, no geometry.
struct TerritoryClaim: Codable, Hashable, Sendable, Identifiable {
    var sectorID: String
    var claimedAt: Date

    var id: String { sectorID }
}

/// Persisted Home Base + expandable sector claims for the canonical atlas.
struct TerritoryState: Codable, Hashable, Sendable {
    /// Exactly one Home Base sector ID among `claims`, or nil when none designated.
    var homeSectorID: String?
    var claims: [TerritoryClaim]
    /// Last time Home Base was set or moved (drives move cooldown).
    var homeMovedAt: Date?

    static let empty = TerritoryState(
        homeSectorID: nil,
        claims: [],
        homeMovedAt: nil
    )

    var claimedSectorIDs: Set<String> {
        Set(claims.map(\.sectorID))
    }

    var claimCount: Int { claims.count }

    func claim(forSectorID sectorID: String) -> TerritoryClaim? {
        claims.first { $0.sectorID == sectorID }
    }

    func isClaimed(_ sectorID: String) -> Bool {
        claimedSectorIDs.contains(sectorID)
    }

    var hasHomeBase: Bool {
        guard let homeSectorID else { return false }
        return isClaimed(homeSectorID)
    }
}

/// Snapshot used by map chrome and Progress for claim / Home Base CTAs.
struct TerritoryPresenceSnapshot: Equatable, Sendable {
    var playerSectorID: String?
    var playerSectorName: String
    var completionFraction: Double
    var isClaimed: Bool
    var isHomeBase: Bool
    var canClaim: Bool
    var canSetHome: Bool
    var homeMoveReadyAt: Date?
    var claimCount: Int

    static let empty = TerritoryPresenceSnapshot(
        playerSectorID: nil,
        playerSectorName: "Frontier",
        completionFraction: 0,
        isClaimed: false,
        isHomeBase: false,
        canClaim: false,
        canSetHome: false,
        homeMoveReadyAt: nil,
        claimCount: 0
    )

    var completionPercent: Int {
        Int((completionFraction * 100).rounded())
    }
}
