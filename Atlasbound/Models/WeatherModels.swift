import Foundation

enum WeatherCondition: String, Codable, CaseIterable, Sendable {
    case clear
    case cloudy
    case rain
    case storm
    case frost
    case snow
    case fog
    case heat
    case wind

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .cloudy: "Cloudy"
        case .rain: "Rain"
        case .storm: "Storm"
        case .frost: "Frost"
        case .snow: "Snow"
        case .fog: "Fog"
        case .heat: "Heat"
        case .wind: "Wind"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .cloudy: "cloud.fill"
        case .rain: "cloud.rain.fill"
        case .storm: "cloud.bolt.rain.fill"
        case .frost: "snowflake"
        case .snow: "cloud.snow.fill"
        case .fog: "cloud.fog.fill"
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
    var hourly: [WeatherHour] = []

    var id: String { cellID }
    var isStale: Bool { expiresAt <= .now }

    func hour(at date: Date) -> WeatherHour? {
        hourly.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    enum CodingKeys: String, CodingKey {
        case cellID, condition, temperatureC, precipitationMM, windKPH, cloudCover, observedAt, expiresAt, hourly
    }

    init(
        cellID: String,
        condition: WeatherCondition,
        temperatureC: Double,
        precipitationMM: Double,
        windKPH: Double,
        cloudCover: Double,
        observedAt: Date,
        expiresAt: Date,
        hourly: [WeatherHour] = []
    ) {
        self.cellID = cellID
        self.condition = condition
        self.temperatureC = temperatureC
        self.precipitationMM = precipitationMM
        self.windKPH = windKPH
        self.cloudCover = cloudCover
        self.observedAt = observedAt
        self.expiresAt = expiresAt
        self.hourly = hourly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cellID = try container.decode(String.self, forKey: .cellID)
        condition = try container.decode(WeatherCondition.self, forKey: .condition)
        temperatureC = try container.decode(Double.self, forKey: .temperatureC)
        precipitationMM = try container.decode(Double.self, forKey: .precipitationMM)
        windKPH = try container.decode(Double.self, forKey: .windKPH)
        cloudCover = try container.decode(Double.self, forKey: .cloudCover)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        hourly = try container.decodeIfPresent([WeatherHour].self, forKey: .hourly) ?? []
    }
}

struct WeatherCacheState: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var snapshots: [String: WeatherSnapshot]
    var lastRefreshAt: Date?

    static func empty() -> WeatherCacheState {
        WeatherCacheState(snapshots: [:], lastRefreshAt: nil)
    }
}
