import Foundation

enum WeatherCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case rain
    case storm
    case frost
    case heat
    case wind

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .storm: "Storm"
        case .frost: "Frost"
        case .heat: "Heat"
        case .wind: "Wind"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .rain: "cloud.rain.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .frost: "snowflake"
        case .heat: "thermometer.sun.fill"
        case .wind: "wind"
        }
    }
}

struct WeatherSnapshot: Codable, Equatable, Sendable, Identifiable {
    let cellID: String
    let condition: WeatherCondition
    let temperatureC: Double
    let precipitationMM: Double
    let windKPH: Double
    let cloudCover: Double
    let observedAt: Date
    let expiresAt: Date

    var id: String { cellID }
    var isStale: Bool { expiresAt <= .now }
}

struct WeatherCacheState: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var snapshots: [String: WeatherSnapshot]
    var lastRefreshAt: Date?

    static func empty() -> WeatherCacheState {
        WeatherCacheState(snapshots: [:], lastRefreshAt: nil)
    }
}
