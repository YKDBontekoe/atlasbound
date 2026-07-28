import Foundation
import CoreLocation

enum TileSizeOption: Int, CaseIterable, Identifiable, Codable, Sendable {
    case twenty = 20

    var id: Int { rawValue }

    var meters: Double { Double(rawValue) }

    var label: String { "\(rawValue) m" }

    /// All new exploration uses one coherent canonical atlas.
    static let `default`: TileSizeOption = .twenty
}

struct ActivitySettings: Codable, Sendable {
    /// Horizontal accuracy worse than this (meters) is discarded.
    var maxHorizontalAccuracy: Double
    /// Minimum movement between accepted samples (meters).
    var minSampleDistance: Double

    static let `default` = ActivitySettings(
        maxHorizontalAccuracy: 25,
        minSampleDistance: 4
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
    var frontierContribution: FrontierSessionContribution?

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var totalXP: Int { discoveryXP + familiarityXP }
}

/// Persisted session record for lifetime activity statistics.
struct PersistedActivityRecord: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let activityType: ActivityType
    let distanceMeters: Double
    let duration: TimeInterval
    let tilesDiscovered: Int
    let totalXP: Int
    let startedAt: Date
    let endedAt: Date
    var frontierPoints: Int?
    var frontierConnectionBonus: Int?
    var frontierCompletionBonus: Int?
    var frontierWeeklyTotal: Int?

    init(from summary: ActivitySummary) {
        self.id = summary.id
        self.activityType = summary.activityType
        self.distanceMeters = summary.distanceMeters
        self.duration = summary.duration
        self.tilesDiscovered = summary.tilesDiscovered
        self.totalXP = summary.totalXP
        self.startedAt = summary.startedAt
        self.endedAt = summary.endedAt
        if let frontier = summary.frontierContribution, frontier.sessionTotal > 0 {
            self.frontierPoints = frontier.tilePoints
            self.frontierConnectionBonus = frontier.connectionBonus > 0 ? frontier.connectionBonus : nil
            self.frontierCompletionBonus = frontier.completionBonus > 0 ? frontier.completionBonus : nil
            self.frontierWeeklyTotal = frontier.weeklyTotalAfter
        }
    }

    var frontierSessionTotal: Int {
        (frontierPoints ?? 0) + (frontierConnectionBonus ?? 0) + (frontierCompletionBonus ?? 0)
    }
}

enum BackgroundRecordingPreference {
    static let storageKey = "atlasbound.backgroundRecordingEnabled"
}

enum AutomaticExplorationPreference {
    static let foregroundKey = "atlasbound.automaticExplorationForeground"
    static let backgroundKey = "atlasbound.automaticExplorationBackground"
}

enum OnboardingPreference {
    static let storageKey = "atlasbound.onboardingVersion"
    static let currentVersion = 2
}

struct LocationSample: Sendable {
    let coordinate: CLLocationCoordinate2D
    let timestamp: Date
    let horizontalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
}
