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

    /// Permanent geocoding is opt-in because Mapbox only permits it for
    /// eligible accounts. Non-permanent responses are treated as a temporary
    /// cache by RegionLookupStore.
    static var permanentGeocodingEnabled: Bool {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MAPBOX_GEOCODING_PERMANENT") as? Bool {
            return value
        }
        return (Bundle.main.object(forInfoDictionaryKey: "MAPBOX_GEOCODING_PERMANENT") as? String)?.lowercased() == "true"
    }

    static func configure() {
        guard let accessToken else {
            #if DEBUG
            debugPrint("MapboxConfiguration: no MBXAccessToken configured")
            #endif
            return
        }
        MapboxOptions.accessToken = accessToken
    }
}
