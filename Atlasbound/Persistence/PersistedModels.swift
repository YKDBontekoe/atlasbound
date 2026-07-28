import Foundation

/// Codable snapshot of a WorldTile for on-disk persistence (no geometry).
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
    var tileSizeMeters: Int

    init(from tile: WorldTile, tileSizeMeters: Int) {
        self.id = tile.id
        self.q = tile.coordinate.q
        self.r = tile.coordinate.r
        self.stateRaw = tile.state.rawValue
        self.masteryXP = tile.masteryXP
        self.visitCount = tile.visitCount
        self.uniqueVisitDays = tile.uniqueVisitDays
        self.activityStampsRaw = tile.activityStamps.map(\.rawValue).sorted()
        self.firstVisitedAt = tile.firstVisitedAt
        self.lastVisitedAt = tile.lastVisitedAt
        self.weeklyCharge = tile.weeklyCharge
        self.regionIDs = tile.regionIDs
        self.tileSizeMeters = tileSizeMeters
    }

    func asWorldTile() -> WorldTile {
        let stamps = Set(activityStampsRaw.compactMap(ActivityType.init(rawValue:)))
        return WorldTile(
            id: id,
            coordinate: TileCoordinate(q: q, r: r),
            state: TileState(rawValue: stateRaw) ?? .fogged,
            masteryXP: masteryXP,
            visitCount: visitCount,
            uniqueVisitDays: uniqueVisitDays,
            activityStamps: stamps,
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
    var tileSizeMeters: Int
}

/// Optional per-grid frontier state — IDs and counters only, no geometry.
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

/// Optional per-grid world-event state — IDs and counters only, no geometry.
struct PersistedWorldEventRecord: Codable, Hashable, Sendable {
    var dayKey: String
    var activeEvent: WorldEventInstance?
    var visitedHotspotIDs: [String]
    var eventProgressCount: Int
    var completedEventIDs: [String]
    var lifetimeEventsCompleted: Int
    var dailyHotspotTileIDs: [String]

    init(from state: WorldEventState) {
        dayKey = state.dayKey
        activeEvent = state.activeEvent
        visitedHotspotIDs = state.visitedHotspotIDs
        eventProgressCount = state.eventProgressCount
        completedEventIDs = state.completedEventIDs
        lifetimeEventsCompleted = state.lifetimeEventsCompleted
        dailyHotspotTileIDs = state.dailyHotspotTileIDs
    }

    func asWorldEventState() -> WorldEventState {
        WorldEventState(
            dayKey: dayKey,
            activeEvent: activeEvent,
            visitedHotspotIDs: visitedHotspotIDs,
            eventProgressCount: eventProgressCount,
            completedEventIDs: completedEventIDs,
            lifetimeEventsCompleted: lifetimeEventsCompleted,
            dailyHotspotTileIDs: dailyHotspotTileIDs
        )
    }
}

struct WorldSaveFile: Codable, Sendable {
    var tiles: [PersistedTileRecord]
    var progressBySize: [String: PersistedProgressRecord]
    var frontierBySize: [String: PersistedFrontierRecord]?
    var eventsBySize: [String: PersistedWorldEventRecord]?

    init(
        tiles: [PersistedTileRecord],
        progressBySize: [String: PersistedProgressRecord],
        frontierBySize: [String: PersistedFrontierRecord]? = nil,
        eventsBySize: [String: PersistedWorldEventRecord]? = nil
    ) {
        self.tiles = tiles
        self.progressBySize = progressBySize
        self.frontierBySize = frontierBySize
        self.eventsBySize = eventsBySize
    }
}
