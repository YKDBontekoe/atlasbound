import Foundation

/// Caps and payouts for Home Base idle drip, hired scouts, and Scout Circuit rewards.
enum IdleConstants {
    /// Matches factory offline catch-up so idle systems stay aligned.
    static let maximumOfflineMinutes = 8 * 60
    /// Home Base material drip cadence while a home sector is set.
    static let homeDripIntervalMinutes = 30
    /// Hard daily ceiling on AFK tile discoveries across the whole roster.
    static let dailyScoutDiscoveryCap = 18
    /// How far scouts search from sector centers when picking fogged tiles.
    static let scoutSearchRadius = 14

    static let homeDripPerInterval: [ItemAmount] = [
        ItemAmount(itemID: "cobble_chip", quantity: 1),
        ItemAmount(itemID: "moss_scrap", quantity: 1),
        ItemAmount(itemID: "trail_ribbon", quantity: 1),
    ]

    /// Extra drip every fourth home interval (~2 h).
    static let homeDripBonusEveryIntervals = 4
    static let homeDripBonus: [ItemAmount] = [
        ItemAmount(itemID: "sector_dust", quantity: 1),
        ItemAmount(itemID: "survey_ink", quantity: 1),
    ]

    static let circuitReward: [ItemAmount] = [
        ItemAmount(itemID: "cobble_chip", quantity: 4),
        ItemAmount(itemID: "trail_ribbon", quantity: 3),
        ItemAmount(itemID: "survey_ink", quantity: 2),
        ItemAmount(itemID: "sector_dust", quantity: 1),
    ]
}

/// Catalog definition for a hireable idle scout.
struct ScoutDefinition: Sendable, Hashable, Identifiable {
    let id: String
    let name: String
    let detail: String
    let symbolName: String
    /// Undiscovered tiles this scout contributes per hour while Home/claims exist.
    let tilesPerHour: Int
    let hireCost: [ItemAmount]
    /// Scout that must already be hired before this one becomes available.
    let prerequisiteScoutID: String?
    /// Scout unlocked in the roster after this one is hired.
    let unlocksScoutID: String?
    let explorerLevel: Int
}

enum ScoutCatalog {
    static let all: [ScoutDefinition] = [
        ScoutDefinition(
            id: "apprentice_scout",
            name: "Apprentice Scout",
            detail: "A local runner who edges into fog near Home Base.",
            symbolName: "figure.walk",
            tilesPerHour: 1,
            hireCost: [
                ItemAmount(itemID: "cobble_chip", quantity: 8),
                ItemAmount(itemID: "trail_ribbon", quantity: 4),
                ItemAmount(itemID: "survey_ink", quantity: 2),
            ],
            prerequisiteScoutID: nil,
            unlocksScoutID: "pathfinder_scout",
            explorerLevel: 1
        ),
        ScoutDefinition(
            id: "pathfinder_scout",
            name: "Pathfinder Scout",
            detail: "Charts claimed neighborhoods and unlocks deeper surveyors.",
            symbolName: "map.fill",
            tilesPerHour: 2,
            hireCost: [
                ItemAmount(itemID: "waystone_shard", quantity: 6),
                ItemAmount(itemID: "sector_dust", quantity: 4),
                ItemAmount(itemID: "brass_rivet", quantity: 2),
            ],
            prerequisiteScoutID: "apprentice_scout",
            unlocksScoutID: "surveyor_scout",
            explorerLevel: 5
        ),
        ScoutDefinition(
            id: "surveyor_scout",
            name: "Surveyor Scout",
            detail: "A careful mapper who presses fog along claim edges.",
            symbolName: "binoculars.fill",
            tilesPerHour: 3,
            hireCost: [
                ItemAmount(itemID: "survey_ink", quantity: 6),
                ItemAmount(itemID: "compass_filament", quantity: 2),
                ItemAmount(itemID: "atlas_insight", quantity: 2),
            ],
            prerequisiteScoutID: "pathfinder_scout",
            unlocksScoutID: "cartographer_scout",
            explorerLevel: 12
        ),
        ScoutDefinition(
            id: "cartographer_scout",
            name: "Cartographer Scout",
            detail: "The lead idle explorer — capped AFK discoveries near your claims.",
            symbolName: "globe.europe.africa.fill",
            tilesPerHour: 4,
            hireCost: [
                ItemAmount(itemID: "atlas_insight", quantity: 6),
                ItemAmount(itemID: "landmark_fibers", quantity: 4),
                ItemAmount(itemID: "waystone_plate", quantity: 2),
            ],
            prerequisiteScoutID: "surveyor_scout",
            unlocksScoutID: "ranger_scout",
            explorerLevel: 20
        ),
        ScoutDefinition(
            id: "ranger_scout",
            name: "Ranger Scout",
            detail: "A far-ranging idle explorer who presses claim edges harder.",
            symbolName: "figure.hiking",
            tilesPerHour: 5,
            hireCost: [
                ItemAmount(itemID: "atlas_insight", quantity: 8),
                ItemAmount(itemID: "waystone_plate", quantity: 4),
                ItemAmount(itemID: "compass_filament", quantity: 4),
            ],
            prerequisiteScoutID: "cartographer_scout",
            unlocksScoutID: "waykeeper_scout",
            explorerLevel: 28
        ),
        ScoutDefinition(
            id: "waykeeper_scout",
            name: "Waykeeper Scout",
            detail: "The apex idle explorer — maximum capped AFK discoveries.",
            symbolName: "shield.checkered",
            tilesPerHour: 6,
            hireCost: [
                ItemAmount(itemID: "atlas_insight", quantity: 12),
                ItemAmount(itemID: "landmark_fibers", quantity: 6),
                ItemAmount(itemID: "waystone_plate", quantity: 6),
                ItemAmount(itemID: "mechanism", quantity: 2),
            ],
            prerequisiteScoutID: "ranger_scout",
            unlocksScoutID: nil,
            explorerLevel: 40
        ),
    ]

    static let byID: [String: ScoutDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static let starterUnlockedID = "apprentice_scout"
}

struct HiredScout: Codable, Hashable, Sendable, Identifiable {
    var definitionID: String
    var hiredAt: Date

    var id: String { definitionID }
}

/// Persisted idle-pack state — counters and scout roster only, never geometry.
struct IdleState: Codable, Hashable, Sendable {
    var hiredScouts: [HiredScout]
    var unlockedScoutIDs: Set<String>
    var lastSimulatedAt: Date
    /// Fractional tile discoveries awaiting the next whole tile.
    var scoutDiscoveryAccumulator: Double
    var scoutDiscoveryDayKey: String?
    var scoutDiscoveriesToday: Int
    var claimedCircuitRewardDayKey: String?
    var homeDripIntervalAccumulator: Int
    /// Completed 30-minute home intervals (drives bonus every fourth).
    var homeDripIntervalsCompleted: Int
    /// Latest offline report for Adventures chrome.
    var lastReport: IdleAdvanceReport?

    static func empty(at date: Date = .now) -> IdleState {
        IdleState(
            hiredScouts: [],
            unlockedScoutIDs: [ScoutCatalog.starterUnlockedID],
            lastSimulatedAt: date,
            scoutDiscoveryAccumulator: 0,
            scoutDiscoveryDayKey: nil,
            scoutDiscoveriesToday: 0,
            claimedCircuitRewardDayKey: nil,
            homeDripIntervalAccumulator: 0,
            homeDripIntervalsCompleted: 0,
            lastReport: nil
        )
    }

    var hiredScoutIDs: Set<String> {
        Set(hiredScouts.map(\.definitionID))
    }

    var totalTilesPerHour: Int {
        hiredScouts.reduce(0) { partial, scout in
            partial + (ScoutCatalog.byID[scout.definitionID]?.tilesPerHour ?? 0)
        }
    }

    func isHired(_ scoutID: String) -> Bool {
        hiredScoutIDs.contains(scoutID)
    }

    func isUnlocked(_ scoutID: String) -> Bool {
        unlockedScoutIDs.contains(scoutID)
    }
}

/// One offline tick summary (not geometry).
struct IdleAdvanceReport: Codable, Hashable, Sendable {
    var simulatedMinutes: Int
    var homeDripItems: [ItemAmount]
    var scoutTileIDs: [String]
    var scoutDiscoveriesGranted: Int
    var at: Date

    /// True when the tick deposited camp goods or granted scout discoveries.
    var hasGatheredRewards: Bool {
        scoutDiscoveriesGranted > 0 || !homeDripItems.isEmpty
    }

    static let empty = IdleAdvanceReport(
        simulatedMinutes: 0,
        homeDripItems: [],
        scoutTileIDs: [],
        scoutDiscoveriesGranted: 0,
        at: .distantPast
    )
}

/// Ephemeral reopen presentation for a fresh idle catch-up (not persisted).
struct IdleWatchSummary: Identifiable, Sendable, Equatable {
    let id: UUID
    let report: IdleAdvanceReport
    /// Daily AFK discovery count after the tick that produced `report`.
    let scoutDiscoveriesToday: Int

    init(
        id: UUID = UUID(),
        report: IdleAdvanceReport,
        scoutDiscoveriesToday: Int
    ) {
        self.id = id
        self.report = report
        self.scoutDiscoveriesToday = scoutDiscoveriesToday
    }
}

enum ScoutHireResult: Equatable, Sendable {
    case hired(ScoutDefinition)
    case denied(String)
}

enum CircuitRewardClaimResult: Equatable, Sendable {
    case claimed([ItemAmount])
    case denied(String)
}
