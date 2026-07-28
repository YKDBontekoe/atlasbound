import Foundation

/// Codable snapshot of a canonical 20 m tile. Geometry remains derived.
struct PersistedTileRecord: Codable, Hashable, Sendable {
    var id: String
    var q: Int
    var r: Int
    var stateRaw: Int
    var masteryXP: Int
    var visitCount: Int
    var uniqueVisitDays: Int
    var activityStampsRaw: [String]
    var firstVisitedAt: Date?
    var lastVisitedAt: Date?
    var weeklyCharge: Int
    var regionIDs: [String]

    init(from tile: WorldTile) {
        id = tile.id
        q = tile.coordinate.q
        r = tile.coordinate.r
        stateRaw = tile.state.rawValue
        masteryXP = tile.masteryXP
        visitCount = tile.visitCount
        uniqueVisitDays = tile.uniqueVisitDays
        activityStampsRaw = tile.activityStamps.map(\.rawValue).sorted()
        firstVisitedAt = tile.firstVisitedAt
        lastVisitedAt = tile.lastVisitedAt
        weeklyCharge = tile.weeklyCharge
        regionIDs = tile.regionIDs
    }

    func asWorldTile() -> WorldTile {
        WorldTile(
            id: id,
            coordinate: TileCoordinate(q: q, r: r),
            state: TileState(rawValue: stateRaw) ?? .fogged,
            masteryXP: masteryXP,
            visitCount: visitCount,
            uniqueVisitDays: uniqueVisitDays,
            activityStamps: Set(activityStampsRaw.compactMap(ActivityType.init(rawValue:))),
            firstVisitedAt: firstVisitedAt,
            lastVisitedAt: lastVisitedAt,
            weeklyCharge: weeklyCharge,
            regionIDs: regionIDs
        )
    }
}

struct PersistedProgressRecord: Codable, Hashable, Sendable {
    var discoveryXPTotal: Int
    var familiarityXPTotal: Int
    var activitiesCompleted: Int
}

struct PersistedFrontierRecord: Codable, Hashable, Sendable {
    var weekKey: String
    var offers: [ExpeditionOffer]
    var activeOfferID: String?
    var completedOfferIDs: [String]
    var weeklyScore: Int
    var connectionBonusesAwarded: [String]
    var chargedTileIDs: [String]
    var bestWeekScore: Int
    var lifetimeCompletedExpeditions: Int

    init(from state: FrontierState) {
        weekKey = state.weekKey
        offers = state.offers
        activeOfferID = state.activeOfferID
        completedOfferIDs = state.completedOfferIDs
        weeklyScore = state.weeklyScore
        connectionBonusesAwarded = state.connectionBonusesAwarded
        chargedTileIDs = state.chargedTileIDs
        bestWeekScore = state.bestWeekScore
        lifetimeCompletedExpeditions = state.lifetimeCompletedExpeditions
    }

    func asFrontierState() -> FrontierState {
        FrontierState(
            weekKey: weekKey,
            offers: offers,
            activeOfferID: activeOfferID,
            completedOfferIDs: completedOfferIDs,
            weeklyScore: weeklyScore,
            connectionBonusesAwarded: connectionBonusesAwarded,
            chargedTileIDs: chargedTileIDs,
            bestWeekScore: bestWeekScore,
            lifetimeCompletedExpeditions: lifetimeCompletedExpeditions
        )
    }
}

struct WorldSaveFile: Codable, Sendable {
    var version: Int
    var tiles: [PersistedTileRecord]
    var progress: PersistedProgressRecord
    var frontier: PersistedFrontierRecord

    init(
        tiles: [PersistedTileRecord],
        progress: PersistedProgressRecord,
        frontier: PersistedFrontierRecord,
        version: Int = JSONFileStore.currentSchemaVersion
    ) {
        self.version = version
        self.tiles = tiles
        self.progress = progress
        self.frontier = frontier
    }
}
