import Foundation
import Combine
import Supabase

/// Periodically mirrors the remaining store snapshots into the account row.
/// Tiles stay normalized in `player_tiles`; the state row contains only
/// Codable domain payloads and never map geometry.
@MainActor
final class CloudStateSync: ObservableObject {
    private let client: SupabaseClient?
    private var task: Task<Void, Never>?

    init(client: SupabaseClient? = SupabaseClientProvider.client) {
        self.client = client
    }

    func hydrate(
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        treasure: TreasureStore,
        inventory: InventoryStore,
        factory: FactoryStore,
        idle: IdleStore,
        skills: SkillStore,
        pinpoint: PinpointStore
    ) async {
        guard let client,
              let userID = try? await client.auth.session.user.id else { return }
        do {
            let rows: [RemoteCloudState] = try await client
                .from("player_state")
                .select()
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else {
                clearLocalState(
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    treasure: treasure,
                    inventory: inventory,
                    factory: factory,
                    idle: idle,
                    skills: skills,
                    pinpoint: pinpoint
                )
                return
            }

            if let save = Self.decode(row.activityHistory, as: LegacyActivitySave.self) {
                activityHistory.replaceCloudState(save)
            } else {
                activityHistory.replaceCloudState(LegacyActivitySave(version: JSONFileStore.currentSchemaVersion, sessions: [], longestDistanceByActivity: [:], totalDistanceByActivity: [:], totalDurationByActivity: [:], sessionCountByActivity: [:]))
            }
            if let save = Self.decode(row.regions, as: LegacyRegionSave.self) {
                regionLookup.replaceCloudState(save)
            } else {
                regionLookup.replaceCloudState(LegacyRegionSave(version: JSONFileStore.currentSchemaVersion, cells: []))
            }
            if let save = Self.decode(row.treasure, as: LegacyTreasureSave.self) { treasure.replaceCloudState(save) } else { treasure.clearCloudState() }
            if let save = Self.decode(row.inventory, as: LegacyInventorySave.self) { inventory.replaceCloudState(save) } else { inventory.clearCloudState() }
            if let save = Self.decode(row.factory, as: LegacyFactorySave.self) { factory.replaceState(save.state) } else { factory.clear() }
            if let save = Self.decode(row.idle, as: LegacyIdleSave.self) { idle.replaceState(save.state) } else { idle.clear() }
            if let save = Self.decode(row.skills, as: LegacySkillSave.self) { skills.replaceState(save.state) } else { skills.clear() }
            if let save = Self.decode(row.pinpoint, as: LegacyPinpointSave.self) { pinpoint.replaceCloudState(save) } else { pinpoint.clearCloudState() }
        } catch {
            // Keep the local cache intact if the account is temporarily offline.
        }
    }

    func start(
        tileStore: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        treasure: TreasureStore,
        inventory: InventoryStore,
        factory: FactoryStore,
        idle: IdleStore,
        skills: SkillStore,
        pinpoint: PinpointStore
    ) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.persist(
                    treasure: treasure,
                    tileStore: tileStore,
                    activityHistory: activityHistory,
                    regionLookup: regionLookup,
                    inventory: inventory,
                    factory: factory,
                    idle: idle,
                    skills: skills,
                    pinpoint: pinpoint
                )
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func persist(
        treasure: TreasureStore,
        tileStore: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        inventory: InventoryStore,
        factory: FactoryStore,
        idle: IdleStore,
        skills: SkillStore,
        pinpoint: PinpointStore
    ) async {
        guard let client,
              let userID = try? await client.auth.session.user.id else { return }

        let row = CloudStateRow(
            userID: userID,
            tileStore: tileStore,
            activityHistory: activityHistory,
            regionLookup: regionLookup,
            treasure: treasure,
            inventory: inventory,
            factory: factory,
            idle: idle,
            skills: skills,
            pinpoint: pinpoint
        )
        do {
            try await client
                .from("player_state")
                .update(row)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch {
            // The next scheduled pass retries transient failures.
        }
    }

    private func clearLocalState(
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        treasure: TreasureStore,
        inventory: InventoryStore,
        factory: FactoryStore,
        idle: IdleStore,
        skills: SkillStore,
        pinpoint: PinpointStore
    ) {
        activityHistory.replaceCloudState(LegacyActivitySave(version: JSONFileStore.currentSchemaVersion, sessions: [], longestDistanceByActivity: [:], totalDistanceByActivity: [:], totalDurationByActivity: [:], sessionCountByActivity: [:]))
        regionLookup.replaceCloudState(LegacyRegionSave(version: JSONFileStore.currentSchemaVersion, cells: []))
        treasure.clearCloudState()
        inventory.clearCloudState()
        factory.clear()
        idle.clear()
        skills.clear()
        pinpoint.clearCloudState()
    }

    private static func decode<T: Decodable>(_ value: AnyJSON, as type: T.Type) -> T? {
        try? value.decode(as: type)
    }
}

@MainActor
private struct CloudStateRow: Encodable {
    let userID: UUID
    let frontier: AnyJSON
    let territory: AnyJSON
    let treasure: AnyJSON
    let inventory: AnyJSON
    let factory: AnyJSON
    let idle: AnyJSON
    let skills: AnyJSON
    let pinpoint: AnyJSON
    let activityHistory: AnyJSON
    let regions: AnyJSON

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case frontier, territory, treasure, inventory, factory, idle, skills, pinpoint
        case activityHistory = "activity_history"
        case regions
    }

    init(
        userID: UUID,
        tileStore: TileStore,
        activityHistory: ActivityHistoryStore,
        regionLookup: RegionLookupStore,
        treasure: TreasureStore,
        inventory: InventoryStore,
        factory: FactoryStore,
        idle: IdleStore,
        skills: SkillStore,
        pinpoint: PinpointStore
    ) {
        self.userID = userID
        frontier = Self.json(PersistedFrontierRecord(from: tileStore.frontierState))
        territory = Self.json(PersistedTerritoryRecord(from: tileStore.territoryState))
        self.treasure = Self.json(LegacyTreasureSave(
            version: JSONFileStore.currentSchemaVersion,
            dailyTrail: treasure.dailyTrail,
            weeklyVault: treasure.weeklyVault,
            relics: treasure.relics,
            completedTrailCount: treasure.completedTrailCount
        ))
        self.inventory = Self.json(CloudInventorySnapshot(
            stacks: inventory.stacks,
            claimedFindIDs: Array(inventory.claimedFindIDs),
            findsClaimedToday: inventory.findsClaimedToday,
            activeEffects: inventory.activeEffects,
            cartographerPins: inventory.cartographerPins,
            lifetimeFindsCollected: inventory.lifetimeFindsCollected
        ))
        self.factory = Self.json(factory.state)
        self.idle = Self.json(idle.state)
        self.skills = Self.json(skills.state)
        self.pinpoint = Self.json(CloudPinpointSnapshot(
            games: pinpoint.gameHistory,
            highScoreWorldwide: pinpoint.highScoreWorldwide,
            highScoreHomeTurf: pinpoint.highScoreHomeTurf,
            gamesPlayed: pinpoint.gamesPlayed,
            exactTileHits: pinpoint.exactTileHits
        ))
        self.activityHistory = Self.json(LegacyActivitySave(
            version: JSONFileStore.currentSchemaVersion,
            sessions: activityHistory.sessions,
            longestDistanceByActivity: activityHistory.longestDistanceByActivity.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            totalDistanceByActivity: activityHistory.totalDistanceByActivity.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            totalDurationByActivity: activityHistory.totalDurationByActivity.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value },
            sessionCountByActivity: activityHistory.sessionCountByActivity.reduce(into: [:]) { $0[$1.key.rawValue] = $1.value }
        ))
        self.regions = Self.json(LegacyRegionSave(
            version: JSONFileStore.currentSchemaVersion,
            cells: Array(regionLookup.cells.values)
        ))
    }

    private static func json<T: Codable>(_ value: T) -> AnyJSON {
        (try? AnyJSON(value)) ?? .object([:])
    }
}

private struct CloudInventorySnapshot: Codable {
    let stacks: [InventoryStack]
    let claimedFindIDs: [String]
    let findsClaimedToday: Int
    let activeEffects: [ActiveItemEffect]
    let cartographerPins: [CartographerPin]
    let lifetimeFindsCollected: Int
}

private struct CloudPinpointSnapshot: Codable {
    let games: [PinpointGame]
    let highScoreWorldwide: Int
    let highScoreHomeTurf: Int
    let gamesPlayed: Int
    let exactTileHits: Int
}

private struct RemoteCloudState: Decodable {
    let treasure: AnyJSON
    let inventory: AnyJSON
    let factory: AnyJSON
    let idle: AnyJSON
    let skills: AnyJSON
    let pinpoint: AnyJSON
    let activityHistory: AnyJSON
    let regions: AnyJSON

    enum CodingKeys: String, CodingKey {
        case treasure, inventory, factory, idle, skills, pinpoint
        case activityHistory = "activity_history"
        case regions
    }
}
