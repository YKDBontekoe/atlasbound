import Foundation

/// Client-scheduled world event kinds (no live ops / network).
enum WorldEventKind: String, Codable, Sendable, CaseIterable {
    case surge
    case beaconRush
    case hotspotCircuit
    case frontierCharge

    var displayName: String {
        switch self {
        case .surge: "XP Surge"
        case .beaconRush: "Beacon Rush"
        case .hotspotCircuit: "Hotspot Circuit"
        case .frontierCharge: "Frontier Charge"
        }
    }

    var iconName: String {
        switch self {
        case .surge: "bolt.fill"
        case .beaconRush: "star.circle.fill"
        case .hotspotCircuit: "circle.hexagongrid.fill"
        case .frontierCharge: "flame.fill"
        }
    }
}

enum WorldEventConstants {
    static let dailyHotspotCount = 6
    static let maxVisibleHotspots = 8
    static let maxPlacePins = 12
    static let beaconRushTilesRequired = 10
    static let hotspotCircuitRequired = 4
    static let completionFamiliarityXP = 40
    static let surgeDiscoveryMultiplier = 1.5
    static let surgeFamiliarityMultiplier = 1.5
    static let frontierScoreMultiplier = 1.5
    /// Extra weekly charge applied on frontier-scoring tiles during Frontier Charge.
    static let frontierChargeBonus = 1
}

/// A resolved, time-bound event instance — IDs and counters only, no geometry.
struct WorldEventInstance: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: WorldEventKind
    let dayKey: String
    let title: String
    let subtitle: String
    var targetSectorID: String?
    var hotspotTileIDs: [String]
    var tilesRequired: Int
    var completionFamiliarityXP: Int
    var discoveryXPMultiplier: Double
    var familiarityXPMultiplier: Double
    var frontierScoreMultiplier: Double
    var windowStart: Date
    var windowEnd: Date

    var isLive: Bool {
        isLive(at: .now)
    }

    func isLive(at date: Date) -> Bool {
        date >= windowStart && date < windowEnd
    }
}

/// Per-grid world-event + daily-highlight state persisted with tile progress.
struct WorldEventState: Codable, Hashable, Sendable {
    var dayKey: String
    var activeEvent: WorldEventInstance?
    var visitedHotspotIDs: [String]
    var eventProgressCount: Int
    var completedEventIDs: [String]
    var lifetimeEventsCompleted: Int
    var dailyHotspotTileIDs: [String]

    static let empty = WorldEventState(
        dayKey: "",
        activeEvent: nil,
        visitedHotspotIDs: [],
        eventProgressCount: 0,
        completedEventIDs: [],
        lifetimeEventsCompleted: 0,
        dailyHotspotTileIDs: []
    )

    var visitedHotspotSet: Set<String> { Set(visitedHotspotIDs) }

    var completedEventSet: Set<String> { Set(completedEventIDs) }

    var progressTowardGoal: Int {
        guard let active = activeEvent else { return 0 }
        switch active.kind {
        case .hotspotCircuit:
            return visitedHotspotIDs.filter { active.hotspotTileIDs.contains($0) }.count
        case .beaconRush:
            return eventProgressCount
        case .surge, .frontierCharge:
            return eventProgressCount
        }
    }

    var isActiveCompleted: Bool {
        guard let active = activeEvent else { return false }
        return completedEventSet.contains(active.id)
    }
}

/// Result of scoring a visit against the active world event / hotspots.
struct WorldEventVisitAward: Sendable, Equatable {
    let tileID: String
    let kind: WorldEventKind
    let progressDelta: Int
    let familiarityXPBonus: Int
    let didComplete: Bool
    let wasHotspotVisit: Bool
}

/// Map annotation for a daily / event hotspot (tile ID only).
struct MapHotspot: Identifiable, Sendable, Equatable {
    let id: String
    let tileID: String
    let isVisited: Bool
    let isEventTarget: Bool
}

/// Places-visited pin for the layers toggle (label + cell key; no hex geometry).
struct PlaceMapPin: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
}
