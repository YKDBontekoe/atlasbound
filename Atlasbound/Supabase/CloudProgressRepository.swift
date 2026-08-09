import Foundation
import Supabase

/// Writes the canonical atlas and lifetime progress to Supabase. The existing
/// store remains the synchronous UI cache; every successful local write also
/// queues this cloud write so the account is the durable source of truth.
@MainActor
final class CloudProgressRepository {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.client) {
        self.client = client
    }

    struct RemoteWorld {
        let tiles: [WorldTile]
        let progress: PersistedProgressRecord
        let frontier: FrontierState
        let territory: TerritoryState
    }

    func loadWorld() async -> RemoteWorld? {
        guard let client,
              let userID = try? await client.auth.session.user.id else { return nil }
        do {
            let tileRows: [RemoteTileRow] = try await client
                .from("player_tiles")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            let progressRows: [RemoteProgressRow] = try await client
                .from("player_progress")
                .select()
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            let stateRows: [RemoteStateRow] = try await client
                .from("player_state")
                .select()
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value

            let progress = progressRows.first.map {
                PersistedProgressRecord(
                    discoveryXPTotal: $0.discoveryXP,
                    familiarityXPTotal: $0.familiarityXP,
                    activitiesCompleted: $0.activitiesCompleted
                )
            } ?? PersistedProgressRecord(discoveryXPTotal: 0, familiarityXPTotal: 0, activitiesCompleted: 0)
            let state = stateRows.first
            let frontier = state.flatMap { try? $0.frontier.decode(as: PersistedFrontierRecord.self).asFrontierState() } ?? .empty
            let territory = state.flatMap { try? $0.territory.decode(as: PersistedTerritoryRecord.self).asTerritoryState() } ?? .empty
            return RemoteWorld(
                tiles: tileRows.map(\.worldTile),
                progress: progress,
                frontier: frontier,
                territory: territory
            )
        } catch {
            return nil
        }
    }

    func persist(
        tiles: [WorldTile],
        progress: PersistedProgressRecord?,
        clearAllTiles: Bool,
        frontier: FrontierState?,
        territory: TerritoryState?
    ) async {
        guard let client,
              let userID = try? await client.auth.session.user.id else { return }

        do {
            if clearAllTiles {
                try await client
                    .from("player_tiles")
                    .delete()
                    .eq("user_id", value: userID.uuidString)
                    .execute()
            }

            if !tiles.isEmpty {
                let rows = tiles.map { CloudTileRow(userID: userID, tile: $0) }
                try await client
                    .from("player_tiles")
                    .upsert(rows, onConflict: "user_id,tile_id")
                    .execute()
            }

            if let progress {
                try await client
                    .from("player_progress")
                    .upsert(CloudProgressRow(userID: userID, progress: progress))
                    .execute()
            }

            if let frontier, let territory {
                let params: [String: AnyJSON] = [
                    "p_frontier": (try? AnyJSON(PersistedFrontierRecord(from: frontier))) ?? .object([:]),
                    "p_territory": (try? AnyJSON(PersistedTerritoryRecord(from: territory))) ?? .object([:])
                ]
                try await client.rpc("save_world_state", params: params).execute()
            }
        } catch {
            // The local store remains authoritative for the current frame; a
            // later sync pass retries failed writes.
        }
    }
}

private struct CloudTileRow: Encodable {
    let userID: UUID
    let tileID: String
    let q: Int
    let r: Int
    let state: Int
    let masteryXP: Int
    let visitCount: Int
    let uniqueVisitDays: Int
    let activityStamps: AnyJSON
    let firstVisitedAt: Date?
    let lastVisitedAt: Date?
    let weeklyCharge: Int
    let regionIDs: AnyJSON

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case tileID = "tile_id"
        case q, r, state
        case masteryXP = "mastery_xp"
        case visitCount = "visit_count"
        case uniqueVisitDays = "unique_visit_days"
        case activityStamps = "activity_stamps"
        case firstVisitedAt = "first_visited_at"
        case lastVisitedAt = "last_visited_at"
        case weeklyCharge = "weekly_charge"
        case regionIDs = "region_ids"
    }

    init(userID: UUID, tile: WorldTile) {
        self.userID = userID
        tileID = tile.id
        q = tile.coordinate.q
        r = tile.coordinate.r
        state = tile.state.rawValue
        masteryXP = tile.masteryXP
        visitCount = tile.visitCount
        uniqueVisitDays = tile.uniqueVisitDays
        activityStamps = (try? AnyJSON(tile.activityStamps.map(\.rawValue).sorted())) ?? .array([])
        firstVisitedAt = tile.firstVisitedAt
        lastVisitedAt = tile.lastVisitedAt
        weeklyCharge = tile.weeklyCharge
        regionIDs = (try? AnyJSON(tile.regionIDs)) ?? .array([])
    }
}

private struct CloudProgressRow: Encodable {
    let userID: UUID
    let discoveryXP: Int
    let familiarityXP: Int
    let activitiesCompleted: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case discoveryXP = "discovery_xp"
        case familiarityXP = "familiarity_xp"
        case activitiesCompleted = "activities_completed"
    }

    init(userID: UUID, progress: PersistedProgressRecord) {
        self.userID = userID
        discoveryXP = progress.discoveryXPTotal
        familiarityXP = progress.familiarityXPTotal
        activitiesCompleted = progress.activitiesCompleted
    }
}

private struct RemoteTileRow: Decodable {
    let tileID: String
    let q: Int
    let r: Int
    let state: Int
    let masteryXP: Int
    let visitCount: Int
    let uniqueVisitDays: Int
    let activityStamps: [String]
    let firstVisitedAt: Date?
    let lastVisitedAt: Date?
    let weeklyCharge: Int
    let regionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case tileID = "tile_id"
        case q, r, state
        case masteryXP = "mastery_xp"
        case visitCount = "visit_count"
        case uniqueVisitDays = "unique_visit_days"
        case activityStamps = "activity_stamps"
        case firstVisitedAt = "first_visited_at"
        case lastVisitedAt = "last_visited_at"
        case weeklyCharge = "weekly_charge"
        case regionIDs = "region_ids"
    }

    var worldTile: WorldTile {
        WorldTile(
            id: tileID,
            coordinate: TileCoordinate(q: q, r: r),
            state: TileState(rawValue: state) ?? .fogged,
            masteryXP: masteryXP,
            visitCount: visitCount,
            uniqueVisitDays: uniqueVisitDays,
            activityStamps: Set(activityStamps.compactMap(ActivityType.init(rawValue:))),
            firstVisitedAt: firstVisitedAt,
            lastVisitedAt: lastVisitedAt,
            weeklyCharge: weeklyCharge,
            regionIDs: regionIDs
        )
    }
}

private struct RemoteProgressRow: Decodable {
    let discoveryXP: Int
    let familiarityXP: Int
    let activitiesCompleted: Int

    enum CodingKeys: String, CodingKey {
        case discoveryXP = "discovery_xp"
        case familiarityXP = "familiarity_xp"
        case activitiesCompleted = "activities_completed"
    }
}

private struct RemoteStateRow: Decodable {
    let frontier: AnyJSON
    let territory: AnyJSON
}
