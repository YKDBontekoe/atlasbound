import Foundation
import Supabase

struct WeatherRepository: Sendable {
    private let client: SupabaseClient?

    init(client: SupabaseClient? = SupabaseClientProvider.authenticatedClient) {
        self.client = client
    }

    func fetch(cellID: String, latitude: Double, longitude: Double) async -> WeatherSnapshot? {
        guard let client else { return nil }
        do {
            let response: WeatherFunctionResponse = try await client.functions.invoke(
                "weather-atlas",
                options: FunctionInvokeOptions(body: WeatherRequest(cellID: cellID, latitude: latitude, longitude: longitude))
            )
            return response.snapshot
        } catch {
            return nil
        }
    }
}

private struct WeatherFunctionResponse: Decodable, Sendable {
    let snapshot: WeatherSnapshot
}

private struct WeatherRequest: Encodable, Sendable {
    let cellID: String
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case cellID = "cell_id"
        case latitude, longitude
    }
}
