import Foundation
import CoreLocation

/// Throttled Mapbox reverse geocoder used for the Places Visited projection.
actor GeocodeLimiter {
    static let shared = GeocodeLimiter()

    private var lastRequest = Date.distantPast
    private let minimumInterval: TimeInterval = 0.15

    func reverseGeocode(at coordinate: CLLocationCoordinate2D) async -> RegionLookupEngine.PlaceLabels? {
        let elapsed = Date().timeIntervalSince(lastRequest)
        if elapsed < minimumInterval {
            try? await Task.sleep(for: .seconds(minimumInterval - elapsed))
        }
        lastRequest = Date()

        guard let token = MapboxConfiguration.accessToken else { return nil }
        var components = URLComponents(string: "https://api.mapbox.com/search/geocode/v6/reverse")
        components?.queryItems = [
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "permanent", value: MapboxConfiguration.permanentGeocodingEnabled ? "true" : "false"),
            URLQueryItem(name: "access_token", value: token)
        ]
        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let features = object["features"] as? [[String: Any]] else { return nil }
            return RegionLookupEngine.labels(fromMapboxFeatures: features)
        } catch {
            return nil
        }
    }
}
