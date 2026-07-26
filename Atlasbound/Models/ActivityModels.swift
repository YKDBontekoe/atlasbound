import Foundation
import CoreLocation

enum TileSizeOption: Int, CaseIterable, Identifiable, Codable, Sendable {
    case sixty = 60
    case eighty = 80
    case hundred = 100

    var id: Int { rawValue }

    var meters: Double { Double(rawValue) }

    var label: String { "\(rawValue) m" }

    static let `default`: TileSizeOption = .eighty
}

struct ActivitySettings: Codable, Sendable {
    var tileSize: TileSizeOption
    /// Horizontal accuracy worse than this (meters) is discarded.
    var maxHorizontalAccuracy: Double
    /// Minimum movement between accepted samples (meters).
    var minSampleDistance: Double

    static let `default` = ActivitySettings(
        tileSize: .default,
        maxHorizontalAccuracy: 50,
        minSampleDistance: 8
    )
}

struct ActivitySummary: Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let distanceMeters: Double
    let sampleCount: Int
    let tilesVisited: Int
    let tilesDiscovered: Int
    let discoveryXP: Int
    let familiarityXP: Int
    let activityType: ActivityType

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var totalXP: Int { discoveryXP + familiarityXP }
}

struct LocationSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
}
