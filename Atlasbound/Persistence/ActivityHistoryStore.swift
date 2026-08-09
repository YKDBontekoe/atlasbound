import Foundation
import Combine

/// Persists finished activity sessions and rolling per-activity aggregates in SQLite.
@MainActor
final class ActivityHistoryStore: ObservableObject {
    static let maxSessions = 100

    @Published private(set) var sessions: [PersistedActivityRecord] = []
    @Published private(set) var longestDistanceByActivity: [ActivityType: Double] = [:]
    @Published private(set) var totalDistanceByActivity: [ActivityType: Double] = [:]
    @Published private(set) var totalDurationByActivity: [ActivityType: TimeInterval] = [:]
    @Published private(set) var sessionCountByActivity: [ActivityType: Int] = [:]

    private let database: AtlasDatabase

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }
        loadFromDisk()
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    func record(_ summary: ActivitySummary) {
        let record = PersistedActivityRecord(from: summary)
        sessions.append(record)
        if sessions.count > Self.maxSessions {
            sessions.removeFirst(sessions.count - Self.maxSessions)
        }

        let type = summary.activityType
        longestDistanceByActivity[type] = max(longestDistanceByActivity[type, default: 0], summary.distanceMeters)
        totalDistanceByActivity[type, default: 0] += summary.distanceMeters
        totalDurationByActivity[type, default: 0] += summary.duration
        sessionCountByActivity[type, default: 0] += 1

        persistToDisk()
    }

    func longestDistance(for activity: ActivityType) -> Double {
        longestDistanceByActivity[activity, default: 0]
    }

    func totalDistance(for activity: ActivityType) -> Double {
        totalDistanceByActivity[activity, default: 0]
    }

    func sessionCount(for activity: ActivityType) -> Int {
        sessionCountByActivity[activity, default: 0]
    }

    func replaceCloudState(_ save: LegacyActivitySave) {
        sessions = Array(save.sessions.suffix(Self.maxSessions))
        longestDistanceByActivity = Dictionary(uniqueKeysWithValues: save.longestDistanceByActivity.compactMap { key, value in
            guard let activity = ActivityType(rawValue: key) else { return nil }
            return (activity, max(0, value))
        })
        totalDistanceByActivity = Dictionary(uniqueKeysWithValues: save.totalDistanceByActivity.compactMap { key, value in
            guard let activity = ActivityType(rawValue: key) else { return nil }
            return (activity, max(0, value))
        })
        totalDurationByActivity = Dictionary(uniqueKeysWithValues: save.totalDurationByActivity.compactMap { key, value in
            guard let activity = ActivityType(rawValue: key) else { return nil }
            return (activity, max(0, value))
        })
        sessionCountByActivity = Dictionary(uniqueKeysWithValues: save.sessionCountByActivity.compactMap { key, value in
            guard let activity = ActivityType(rawValue: key) else { return nil }
            return (activity, max(0, value))
        })
        database.removeActivityAggregates(except: Set(
            Array(longestDistanceByActivity.keys)
                + Array(totalDistanceByActivity.keys)
                + Array(totalDurationByActivity.keys)
                + Array(sessionCountByActivity.keys)
        ))
        persistToDisk()
    }

    func resetLocalSession() {
        sessions = []
        longestDistanceByActivity = [:]
        totalDistanceByActivity = [:]
        totalDurationByActivity = [:]
        sessionCountByActivity = [:]
    }

    private func loadFromDisk() {
        let loaded = database.loadActivities()
        sessions = loaded.sessions
        longestDistanceByActivity = loaded.longest
        totalDistanceByActivity = loaded.totalDistance
        totalDurationByActivity = loaded.totalDuration
        sessionCountByActivity = loaded.sessionCount
    }

    private func persistToDisk() {
        database.replaceActivitySessions(sessions)
        for type in Set(
            Array(longestDistanceByActivity.keys)
                + Array(totalDistanceByActivity.keys)
                + Array(totalDurationByActivity.keys)
                + Array(sessionCountByActivity.keys)
        ) {
            database.upsertActivityAggregate(
                type: type,
                longest: longestDistanceByActivity[type, default: 0],
                totalDistance: totalDistanceByActivity[type, default: 0],
                totalDuration: totalDurationByActivity[type, default: 0],
                sessionCount: sessionCountByActivity[type, default: 0]
            )
        }
    }
}
