import Foundation
import Combine

/// Persists finished activity sessions and rolling per-activity aggregates.
@MainActor
final class ActivityHistoryStore: ObservableObject {
    static let maxSessions = 100

    @Published private(set) var sessions: [PersistedActivityRecord] = []
    @Published private(set) var longestDistanceByActivity: [ActivityType: Double] = [:]
    @Published private(set) var totalDistanceByActivity: [ActivityType: Double] = [:]
    @Published private(set) var totalDurationByActivity: [ActivityType: TimeInterval] = [:]
    @Published private(set) var sessionCountByActivity: [ActivityType: Int] = [:]

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let fileName = "atlasbound-activities.json"

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = docs.appendingPathComponent(Self.fileName)
        }
        loadFromDisk()
    }

    func record(_ summary: ActivitySummary, tileSizeMeters: Int) {
        let record = PersistedActivityRecord(from: summary, tileSizeMeters: tileSizeMeters)
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

    // MARK: - Disk

    private struct SaveFile: Codable {
        var sessions: [PersistedActivityRecord]
        var longestDistanceByActivity: [String: Double]
        var totalDistanceByActivity: [String: Double]
        var totalDurationByActivity: [String: Double]
        var sessionCountByActivity: [String: Int]
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let save = try decoder.decode(SaveFile.self, from: data)
            sessions = save.sessions
            longestDistanceByActivity = Self.decodeActivityMap(save.longestDistanceByActivity)
            totalDistanceByActivity = Self.decodeActivityMap(save.totalDistanceByActivity)
            totalDurationByActivity = Self.decodeActivityMap(save.totalDurationByActivity)
            sessionCountByActivity = Self.decodeActivityCountMap(save.sessionCountByActivity)
        } catch {
            sessions = []
            longestDistanceByActivity = [:]
            totalDistanceByActivity = [:]
            totalDurationByActivity = [:]
            sessionCountByActivity = [:]
        }
    }

    private func persistToDisk() {
        let save = SaveFile(
            sessions: sessions,
            longestDistanceByActivity: Self.encodeActivityMap(longestDistanceByActivity),
            totalDistanceByActivity: Self.encodeActivityMap(totalDistanceByActivity),
            totalDurationByActivity: Self.encodeActivityMap(totalDurationByActivity),
            sessionCountByActivity: Self.encodeActivityCountMap(sessionCountByActivity)
        )
        do {
            let data = try encoder.encode(save)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep in-memory state on write failure.
        }
    }

    private static func encodeActivityMap<T>(_ map: [ActivityType: T]) -> [String: T] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value) })
    }

    private static func decodeActivityMap<T>(_ map: [String: T]) -> [ActivityType: T] {
        var result: [ActivityType: T] = [:]
        for (key, value) in map {
            if let type = ActivityType(rawValue: key) {
                result[type] = value
            }
        }
        return result
    }

    private static func encodeActivityCountMap(_ map: [ActivityType: Int]) -> [String: Int] {
        encodeActivityMap(map)
    }

    private static func decodeActivityCountMap(_ map: [String: Int]) -> [ActivityType: Int] {
        decodeActivityMap(map)
    }
}
