import Foundation
import Combine

@MainActor
final class IdleStore: ObservableObject {
    static let schemaVersion = 1

    @Published private(set) var state: IdleState

    private let database: AtlasDatabase

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, now: Date = .now) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }

        if let loaded = self.database.loadIdleState() {
            state = Self.sanitized(loaded)
        } else {
            state = .empty(at: now)
            self.database.saveIdleState(state)
        }
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    var hiredScouts: [HiredScout] { state.hiredScouts }
    var unlockedScoutIDs: Set<String> { state.unlockedScoutIDs }
    var lastReport: IdleAdvanceReport? { state.lastReport }
    var scoutDiscoveriesToday: Int { state.scoutDiscoveriesToday }
    var claimedCircuitRewardDayKey: String? { state.claimedCircuitRewardDayKey }

    func replaceState(_ next: IdleState) {
        guard next != state else { return }
        state = next
        persist()
    }

    func update(_ transform: (inout IdleState) -> Void) {
        var next = state
        transform(&next)
        replaceState(next)
    }

    func clear(at date: Date = .now) {
        state = .empty(at: date)
        persist()
    }

    func resetLocalSession() {
        state = .empty(at: .now)
    }

    private func persist() {
        database.saveIdleState(state)
    }

    private static func sanitized(_ state: IdleState) -> IdleState {
        var next = state
        let validIDs = Set(ScoutCatalog.all.map(\.id))
        next.hiredScouts = state.hiredScouts.filter { validIDs.contains($0.definitionID) }
        next.unlockedScoutIDs = state.unlockedScoutIDs.intersection(validIDs)
        if next.unlockedScoutIDs.isEmpty {
            next.unlockedScoutIDs = [ScoutCatalog.starterUnlockedID]
        }
        // Re-derive unlocks from hire chain so saves stay consistent.
        next.unlockedScoutIDs.insert(ScoutCatalog.starterUnlockedID)
        for scout in next.hiredScouts {
            if let unlocks = ScoutCatalog.byID[scout.definitionID]?.unlocksScoutID {
                next.unlockedScoutIDs.insert(unlocks)
            }
        }
        next.scoutDiscoveryAccumulator = max(0, next.scoutDiscoveryAccumulator)
        next.scoutDiscoveriesToday = max(0, next.scoutDiscoveriesToday)
        next.homeDripIntervalAccumulator = max(0, next.homeDripIntervalAccumulator)
        next.homeDripIntervalsCompleted = max(0, next.homeDripIntervalsCompleted)
        if let report = next.lastReport {
            next.lastReport = IdleAdvanceReport(
                simulatedMinutes: max(0, report.simulatedMinutes),
                homeDripItems: report.homeDripItems.filter {
                    ItemCatalog.definition(for: $0.itemID) != nil && $0.quantity > 0
                },
                scoutTileIDs: report.scoutTileIDs.filter { !$0.isEmpty },
                scoutDiscoveriesGranted: max(0, report.scoutDiscoveriesGranted),
                at: report.at
            )
        }
        return next
    }
}

#if DEBUG
extension IdleStore {
    func debugHireAll(at date: Date = .now) {
        update { state in
            state.hiredScouts = ScoutCatalog.all.map { HiredScout(definitionID: $0.id, hiredAt: date) }
            state.unlockedScoutIDs = Set(ScoutCatalog.all.map(\.id))
        }
    }
}
#endif
