import Foundation
import MapboxMaps

/// Initializes Mapbox exactly once before any map view is created.
enum MapboxConfiguration {
    static var accessToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MBXAccessToken") as? String,
              !value.isEmpty,
              !value.hasPrefix("$(") else { return nil }
        return value
    }

    static func configure() {
        guard let accessToken else { return }
        MapboxOptions.accessToken = accessToken
    }
}
