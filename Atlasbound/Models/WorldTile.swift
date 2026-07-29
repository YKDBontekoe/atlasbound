import Foundation

/// Axial hex coordinate (flat-top). Stable across sessions for a given tile size.
struct TileCoordinate: Hashable, Codable, Sendable, Comparable {
    let q: Int
    let r: Int

    var s: Int { -q - r }

    static func < (lhs: TileCoordinate, rhs: TileCoordinate) -> Bool {
        lhs.q == rhs.q ? lhs.r < rhs.r : lhs.q < rhs.q
    }
}

enum TileState: Int, Codable, Sendable, CaseIterable {
    case fogged = 0
    case discovered = 1
    case explored = 2
    case surveyed = 3
    case mastered = 4
    case legendary = 5

    var displayName: String {
        switch self {
        case .fogged: "Fogged"
        case .discovered: "Discovered"
        case .explored: "Explored"
        case .surveyed: "Surveyed"
        case .mastered: "Mastered"
        case .legendary: "Legendary"
        }
    }
}

enum ActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case walk
    case run
    case cycle
    case hike
    case drive
    case publicTransport
    case unknown

    /// Activities the player can choose before recording (excludes `.unknown`).
    static var selectableCases: [ActivityType] {
        allCases.filter { $0 != .unknown }
    }

}

/// In-memory / domain tile. Geometry is derived from id + tile size, not stored.
struct WorldTile: Identifiable, Hashable, Sendable {
    let id: String
    let coordinate: TileCoordinate
    var state: TileState
    var masteryXP: Int
    var visitCount: Int
    var uniqueVisitDays: Int
    var activityStamps: Set<ActivityType>
    var firstVisitedAt: Date?
    var lastVisitedAt: Date?
    var weeklyCharge: Int
    var regionIDs: [String]

    init(
        id: String,
        coordinate: TileCoordinate,
        state: TileState = .fogged,
        masteryXP: Int = 0,
        visitCount: Int = 0,
        uniqueVisitDays: Int = 0,
        activityStamps: Set<ActivityType> = [],
        firstVisitedAt: Date? = nil,
        lastVisitedAt: Date? = nil,
        weeklyCharge: Int = 0,
        regionIDs: [String] = []
    ) {
        self.id = id
        self.coordinate = coordinate
        self.state = state
        self.masteryXP = masteryXP
        self.visitCount = visitCount
        self.uniqueVisitDays = uniqueVisitDays
        self.activityStamps = activityStamps
        self.firstVisitedAt = firstVisitedAt
        self.lastVisitedAt = lastVisitedAt
        self.weeklyCharge = weeklyCharge
        self.regionIDs = regionIDs
    }

    var isDiscovered: Bool { state != .fogged }
}

/// Places-visited pin for the optional map layer.
struct PlaceMapPin: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
}
