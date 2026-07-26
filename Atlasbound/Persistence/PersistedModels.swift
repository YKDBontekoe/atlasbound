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

struct WorldSaveFile: Codable, Sendable {
    var tiles: [PersistedTileRecord]
    var progressBySize: [String: PersistedProgressRecord]
}
