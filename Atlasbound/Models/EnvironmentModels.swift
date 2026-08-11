import Foundation

/// Broad, real-world character for an atlas area. Geometry is never persisted;
/// this is a short-lived interpretation of provider data around a tile cell.
enum AtlasBiome: String, Codable, CaseIterable, Sendable, Identifiable {
    case open
    case green
    case urban
    case industrial
    case highland
    case waterside
    case heritage

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .open: "Open country"
        case .green: "Greenbelt"
        case .urban: "City fabric"
        case .industrial: "Works district"
        case .highland: "Highland"
        case .waterside: "Waterside"
        case .heritage: "Heritage site"
        }
    }

    var symbolName: String {
        switch self {
        case .open: "sun.max.fill"
        case .green: "leaf.fill"
        case .urban: "building.2.fill"
        case .industrial: "gearshape.2.fill"
        case .highland: "mountain.2.fill"
        case .waterside: "water.waves"
        case .heritage: "building.columns.fill"
        }
    }
}

enum AtlasBiomeTrait: String, Codable, CaseIterable, Sendable, Hashable {
    case trail
    case park
    case forest
    case river
    case lake
    case coast
    case steep
    case dense
    case landmark
}

struct BiomeSnapshot: Codable, Equatable, Sendable, Identifiable {
    let cellID: String
    let primary: AtlasBiome
    let traits: Set<AtlasBiomeTrait>
    let resolvedAt: Date
    let expiresAt: Date

    var id: String { cellID }
    var isStale: Bool { expiresAt <= .now }

    func has(_ trait: AtlasBiomeTrait) -> Bool { traits.contains(trait) }
}

struct BiomeCacheState: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var snapshots: [String: BiomeSnapshot]
    var lastRefreshAt: Date?

    static func empty() -> BiomeCacheState {
        BiomeCacheState(snapshots: [:], lastRefreshAt: nil)
    }
}

/// A point-in-time value used by the 24-hour forecast ribbon.
struct WeatherHour: Codable, Equatable, Sendable, Identifiable {
    let date: Date
    let condition: WeatherCondition
    let temperatureC: Double
    let apparentTemperatureC: Double
    let precipitationMM: Double
    let precipitationProbability: Double
    let snowfallCM: Double
    let windKPH: Double
    let windGustKPH: Double
    let windDirection: Double
    let cloudCover: Double
    let visibilityMeters: Double

    var id: Date { date }
}

/// Pure factory-facing modifier bundle. Values are intentionally bounded by
/// EnvironmentalModifierEngine so weather remains an opportunity, not a stop.
struct EnvironmentalModifiers: Equatable, Sendable {
    var cropYield: Double = 1
    var extractionYield: Double = 1
    var solarPower: Double = 1
    var windPower: Double = 1
    var roadThroughput: Double = 1
    var waterYield: Double = 1
    var processingSpeed: Double = 1
    var researchSpeed: Double = 1

    static let neutral = EnvironmentalModifiers()
}

/// Compact, privacy-preserving activity route. Waypoints are atlas tile IDs
/// and elapsed time only; replay geometry is reconstructed with hexLine.
struct JourneyWaypoint: Codable, Hashable, Sendable {
    let tileID: String
    let elapsedSeconds: Int
}

enum JourneyMomentKind: String, Codable, Sendable {
    case discovery
    case fieldFind
    case biomeChanged
    case weatherChanged
    case pulse
    case frontier
    case regionalEvent
}

struct JourneyMoment: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let kind: JourneyMomentKind
    let tileID: String
    let elapsedSeconds: Int
    let title: String
    let detail: String
}

struct JourneyTrack: Codable, Hashable, Sendable {
    let waypoints: [JourneyWaypoint]
    let moments: [JourneyMoment]

    var isEmpty: Bool { waypoints.isEmpty }
}
