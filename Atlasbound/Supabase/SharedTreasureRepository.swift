import Foundation
import CoreLocation
import Supabase

/// Server boundary for shared treasure events. Clients cannot create or claim rows directly.
final class SharedTreasureRepository {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.authenticatedClient) {
        self.client = client
    }

    func nearby(around coordinate: CLLocationCoordinate2D, radiusMeters: Double = 5_000) async -> [SharedTreasureEvent]? {
        guard let client else { return nil }
        do {
            return try await client
                .rpc("nearby_shared_treasures", params: [
                    "p_latitude": try! AnyJSON(coordinate.latitude),
                    "p_longitude": try! AnyJSON(coordinate.longitude),
                    "p_radius_meters": try! AnyJSON(radiusMeters)
                ])
                .execute()
                .value
        } catch {
            return nil
        }
    }

    func spawn(request: SharedTreasureSpawnRequest) async -> SharedTreasureEvent? {
        guard let client else { return nil }
        do {
            return try await client.functions.invoke(
                "spawn-shared-treasure",
                options: FunctionInvokeOptions(body: request)
            )
        } catch {
            return nil
        }
    }

    func claim(eventID: UUID, at coordinate: CLLocationCoordinate2D) async -> SharedTreasureClaimResult? {
        guard let client else { return nil }
        do {
            return try await client
                .rpc("claim_shared_treasure", params: [
                    "p_event_id": try! AnyJSON(eventID.uuidString),
                    "p_latitude": try! AnyJSON(coordinate.latitude),
                    "p_longitude": try! AnyJSON(coordinate.longitude)
                ])
                .execute()
                .value
        } catch {
            return nil
        }
    }
}
