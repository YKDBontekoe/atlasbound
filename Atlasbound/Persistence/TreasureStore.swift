import Foundation
import Combine

@MainActor
final class TreasureStore: ObservableObject {
    @Published private(set) var dailyTrail: TreasureTrail?
    @Published private(set) var weeklyVault: WeeklyVaultState = .empty
    @Published private(set) var relics: [RelicRecord] = []
    @Published private(set) var completedTrailCount = 0
    @Published var pendingEncounter: TreasureEncounter?
    @Published var latestReward: TreasureReward?

    private let database: AtlasDatabase
    private let engine = TreasureEventEngine()

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }
        load()
        refreshCalendarState()
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    var currentTarget: LandmarkTarget? {
        if weeklyVault.isUnlocked, let target = weeklyVault.target {
            return target
        }
        return dailyTrail?.currentTarget
    }

    var trailProgressLabel: String {
        guard let trail = dailyTrail else { return "Preparing…" }
        return "\(min(trail.currentStageIndex, TreasureConstants.stagesPerTrail))/\(TreasureConstants.stagesPerTrail)"
    }

    func replaceCloudState(_ save: LegacyTreasureSave) {
        dailyTrail = save.dailyTrail
        weeklyVault = save.weeklyVault
        relics = save.relics
        completedTrailCount = max(0, save.completedTrailCount)
        pendingEncounter = nil
        latestReward = nil
        persist()
    }

    func clearCloudState() {
        replaceCloudState(LegacyTreasureSave(
            version: JSONFileStore.currentSchemaVersion,
            dailyTrail: nil,
            weeklyVault: .empty,
            relics: [],
            completedTrailCount: 0
        ))
    }

    func resetLocalSession() {
        dailyTrail = nil
        weeklyVault = .empty
        relics = []
        completedTrailCount = 0
        pendingEncounter = nil
        latestReward = nil
    }

    func ensureTrail(anchor: TileCoordinate, tileEngine: TileEngine, date: Date = .now) {
        refreshCalendarState(date: date)
        let dayKey = TreasureEventEngine.localDayKey(for: date)
        guard dailyTrail?.dayKey != dayKey else { return }
        dailyTrail = engine.makeFallbackTrail(anchor: anchor, tileEngine: tileEngine, dayKey: dayKey)
        persist()
    }

    func replaceTrailTargets(_ targets: [LandmarkTarget], date: Date = .now) {
        guard targets.count >= TreasureConstants.stagesPerTrail * 2 else { return }
        let dayKey = TreasureEventEngine.localDayKey(for: date)
        guard dailyTrail?.dayKey == dayKey, dailyTrail?.currentStageIndex == 0 else { return }
        dailyTrail = engine.makeTrail(dayKey: dayKey, targets: targets)
        persist()
    }

    /// Grants an extra free trail reroll (e.g. Trail Reroll Token / Ribboned Cache Key).
    func grantFreeReroll(date: Date = .now) {
        refreshCalendarState(date: date)
        guard var trail = dailyTrail, !trail.isCompleted else { return }
        trail.freeRerollsRemaining += 1
        dailyTrail = trail
        persist()
    }

    func reroll(anchor: TileCoordinate, tileEngine: TileEngine, date: Date = .now) {
        guard var trail = dailyTrail, trail.freeRerollsRemaining > 0, !trail.isCompleted else { return }
        let dayKey = TreasureEventEngine.localDayKey(for: date)
        var replacement = engine.makeFallbackTrail(
            anchor: TileCoordinate(q: anchor.q + 3, r: anchor.r - 2),
            tileEngine: tileEngine,
            dayKey: "\(dayKey):reroll"
        )
        replacement = TreasureTrail(
            id: "trail:\(dayKey)",
            dayKey: dayKey,
            stages: replacement.stages,
            currentStageIndex: 0,
            isCompleted: false,
            freeRerollsRemaining: trail.freeRerollsRemaining - 1
        )
        trail = replacement
        dailyTrail = trail
        pendingEncounter = nil
        persist()
    }

    func processVisitedTileIDs(_ tileIDs: [String]) {
        guard pendingEncounter == nil else { return }
        if weeklyVault.isUnlocked,
           let target = weeklyVault.target,
           tileIDs.contains(target.tileID) {
            pendingEncounter = TreasureEncounter(id: target.id, target: target, stageNumber: 0, isVault: true)
            return
        }
        guard let trail = dailyTrail,
              let target = trail.currentTarget,
              tileIDs.contains(target.tileID) else { return }
        pendingEncounter = TreasureEncounter(
            id: target.id,
            target: target,
            stageNumber: trail.currentStageIndex + 1,
            isVault: false
        )
    }

    @discardableResult
    func resolveEncounter(choice: TreasureChoice, date: Date = .now) -> TreasureReward? {
        guard let encounter = pendingEncounter else { return nil }
        pendingEncounter = nil

        if encounter.isVault {
            guard weeklyVault.isUnlocked, !weeklyVault.isCompleted else { return nil }
            weeklyVault.isCompleted = true
            let distance = encounter.target.distanceMeters
            let relic = engine.relic(
                seed: "\(weeklyVault.weekKey):vault",
                landmarkName: encounter.target.name,
                choice: choice,
                isVault: true,
                distanceMeters: distance,
                date: date
            )
            relics.append(relic)
            let reward = TreasureReward(
                id: UUID(),
                relic: relic,
                familiarityXP: engine.completionFamiliarityXP(isVault: true, distanceMeters: distance),
                grantedVaultKey: false
            )
            latestReward = reward
            persist()
            return reward
        }

        guard var trail = dailyTrail,
              trail.stages.indices.contains(trail.currentStageIndex),
              !trail.stages[trail.currentStageIndex].isCompleted else { return nil }
        trail.stages[trail.currentStageIndex].selectedChoice = choice
        trail.stages[trail.currentStageIndex].isCompleted = true
        trail.currentStageIndex += 1
        guard trail.currentStageIndex >= trail.stages.count else {
            dailyTrail = trail
            persist()
            return nil
        }

        trail.isCompleted = true
        dailyTrail = trail
        completedTrailCount += 1
        weeklyVault.keys = min(TreasureConstants.keysRequiredForVault, weeklyVault.keys + 1)
        let distance = encounter.target.distanceMeters
        let relic = engine.relic(
            seed: "\(trail.dayKey):\(choice.rawValue)",
            landmarkName: encounter.target.name,
            choice: choice,
            isVault: false,
            distanceMeters: distance,
            date: date
        )
        relics.append(relic)
        let reward = TreasureReward(
            id: UUID(),
            relic: relic,
            familiarityXP: engine.completionFamiliarityXP(isVault: false, distanceMeters: distance),
            grantedVaultKey: true
        )
        latestReward = reward
        persist()
        return reward
    }

    func ensureVaultTarget(anchor: TileCoordinate, tileEngine: TileEngine) {
        refreshCalendarState()
        guard weeklyVault.isUnlocked, weeklyVault.target == nil else { return }
        weeklyVault.target = engine.makeVaultTarget(
            anchor: anchor,
            tileEngine: tileEngine,
            weekKey: weeklyVault.weekKey
        )
        persist()
    }

    private func refreshCalendarState(date: Date = .now) {
        var didChange = false
        let weekKey = TreasureEventEngine.isoWeekKey(for: date)
        if weeklyVault.weekKey != weekKey {
            weeklyVault = WeeklyVaultState(weekKey: weekKey, keys: 0, target: nil, isCompleted: false)
            didChange = true
        }
        if let trail = dailyTrail, trail.dayKey != TreasureEventEngine.localDayKey(for: date) {
            dailyTrail = nil
            pendingEncounter = nil
            didChange = true
        }
        if didChange {
            persist()
        }
    }

    private func load() {
        guard let save = database.loadTreasure() else { return }
        dailyTrail = save.dailyTrail
        weeklyVault = save.weeklyVault
        relics = save.relics
        completedTrailCount = save.completedTrailCount
    }

    private func persist() {
        database.saveTreasure(
            dailyTrail: dailyTrail,
            weeklyVault: weeklyVault,
            relics: relics,
            completedTrailCount: completedTrailCount
        )
    }
}
