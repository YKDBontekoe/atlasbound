import Foundation
import Supabase

/// Guest-safe, read-only environmental lookup. The Edge Function owns Mapbox
/// credentials and returns only our coarse biome enum/traits.
struct BiomeRepository: Sendable {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.client) {
        self.client = client
    }

    func fetch(cellID: String, latitude: Double, longitude: Double) async -> BiomeSnapshot? {
        guard let client else { return nil }
        do {
            let response: BiomeFunctionResponse = try await client.functions.invoke(
                "environment-atlas",
                options: FunctionInvokeOptions(body: BiomeRequest(cellID: cellID, latitude: latitude, longitude: longitude))
            )
            return response.snapshot
        } catch {
            return nil
        }
    }
}

private struct BiomeFunctionResponse: Decodable, Sendable { let snapshot: BiomeSnapshot }

private struct BiomeRequest: Encodable, Sendable {
    let cellID: String
    let latitude: Double
    let longitude: Double
    enum CodingKeys: String, CodingKey { case cellID = "cell_id"; case latitude, longitude }
}
