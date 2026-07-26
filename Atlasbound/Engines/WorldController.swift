import Foundation
import CoreLocation
import Combine

/// Coordinates recording, tile conversion, progression, and persistence for a session.
@MainActor
final class WorldController: ObservableObject {
    @Published private(set) var liveRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var sessionVisitedTileIDs: Set<String> = []
    @Published private(set) var sessionDiscoveredCount = 0
    @Published private(set) var discoveryStreak = 0
    @Published private(set) var streakExpiresAt: Date?
    @Published private(set) var lastSummary: ActivitySummary?
    @Published var showSummary = false
    @Published var showLayers = false

    /// Soft regional label until Region Engine exists.
    let regionName = "Dordrecht"

    let recorder: ActivityRecorder
    let store: TileStore
    private let progression = ProgressionEngine()

    /// Tiles mutated during the active session (merged into store on stop).
    private var sessionTiles: [String: WorldTile] = [:]
    private var sessionProgress = SessionProgress.empty

    init(store: TileStore, recorder: ActivityRecorder? = nil) {
        self.store = store
        self.recorder = recorder ?? ActivityRecorder()
        syncRecorderSettings()

        self.recorder.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        syncTileSizeToActivity()
    }

    var isRecording: Bool { recorder.isRecording }
    var isPaused: Bool { recorder.isPaused }

    var tileEngine: TileEngine { store.tileEngine }

    /// Placeholder neighbourhood completion until regions ship.
    var regionCompletionPercent: Double {
        let discovered = Double(store.discoveredTiles.count)
        return min(100, (discovered / 400.0) * 100.0)
    }

    var streakMultiplier: Double {
        1.0 + min(1.0, Double(discoveryStreak) * 0.1)
    }

    var streakProgress: Double {
        guard discoveryStreak > 0 else { return 0 }
        return Double(discoveryStreak % 10) / 10.0
    }

    func nearbyUndiscoveredCount(around coordinate: CLLocationCoordinate2D?, radius: Int = 3) -> Int {
        guard let coordinate else { return 0 }
        let engine = tileEngine
        let center = engine.axialCoordinate(for: coordinate)
        return engine.ring(around: center, radius: radius).filter { axial in
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            let tile = store.tiles[id]
            return tile == nil || tile?.state == .fogged
        }.count
    }

    /// Fog hexes around the user for the active map wash.
    func nearbyFogTiles(around coordinate: CLLocationCoordinate2D?, radius: Int = 5) -> [TileCoordinate] {
        guard let coordinate else { return [] }
        let engine = tileEngine
        let center = engine.axialCoordinate(for: coordinate)
        return engine.ring(around: center, radius: radius).filter { axial in
            let id = TileEngine.makeTileID(q: axial.q, r: axial.r, sizeMeters: engine.tileSizeMeters)
            let tile = store.tiles[id] ?? sessionTiles[id]
            return tile == nil || tile?.state == .fogged
        }
    }

    func prepareLocation() {
        recorder.requestAuthorization()
        recorder.startMonitoringIfNeeded()
        syncTileSizeToActivity()
    }

    /// Activity selects the reveal grid — players never pick tile size manually.
    func setActivityType(_ type: ActivityType) {
        guard !recorder.isRecording else { return }
        recorder.activityType = type
        syncTileSizeToActivity()
    }

    func startActivity() {
        syncTileSizeToActivity()
        liveRoute = []
        sessionVisitedTileIDs = []
        sessionDiscoveredCount = 0
        discoveryStreak = 0
        streakExpiresAt = nil
        sessionTiles = [:]
        sessionProgress = .empty
        lastSummary = nil
        recorder.start()
    }

    private func syncTileSizeToActivity() {
        let option = recorder.activityType.tileSize
        guard store.tileSize != option else {
            syncRecorderSettings()
            return
        }
        store.tileSize = option
        syncRecorderSettings()
    }

    func pauseActivity() {
        recorder.pause()
    }

    func resumeActivity() {
        recorder.resume()
    }

    func togglePause() {
        recorder.togglePause()
    }

    func stopActivity() {
        guard let result = recorder.stop() else { return }

        let engine = tileEngine
        let covering = engine.tileIDsCoveringRoute(result.samples)
        processTileIDs(covering, at: result.endedAt, activity: recorder.activityType)

        store.applySessionProgress(sessionProgress, updatedTiles: sessionTiles)

        let summary = ActivitySummary(
            id: UUID(),
            startedAt: result.startedAt,
            endedAt: result.endedAt,
            distanceMeters: result.distance,
            sampleCount: result.samples.count,
            tilesVisited: sessionProgress.tilesVisited,
            tilesDiscovered: sessionProgress.tilesDiscovered,
            discoveryXP: sessionProgress.discoveryXP,
            familiarityXP: sessionProgress.familiarityXP,
            activityType: recorder.activityType
        )
        lastSummary = summary
        showSummary = true
        discoveryStreak = 0
        streakExpiresAt = nil
    }

    private func syncRecorderSettings() {
        recorder.updateSettings(
            ActivitySettings(
                tileSize: store.tileSize,
                maxHorizontalAccuracy: ActivitySettings.default.maxHorizontalAccuracy,
                minSampleDistance: ActivitySettings.default.minSampleDistance
            )
        )
    }

    private func handleSample(_ sample: LocationSample) {
        liveRoute.append(sample.coordinate)
        let engine = tileEngine

        if let previous = recorder.samples.dropLast().last {
            let line = TileEngine.hexLine(
                from: engine.axialCoordinate(for: previous.coordinate),
                to: engine.axialCoordinate(for: sample.coordinate)
            )
            let ids = line.map {
                TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: engine.tileSizeMeters)
            }
            processTileIDs(ids, at: sample.timestamp, activity: recorder.activityType)
        } else {
            processTileIDs(
                [engine.tileID(for: sample.coordinate)],
                at: sample.timestamp,
                activity: recorder.activityType
            )
        }
    }

    private func processTileIDs(_ ids: [String], at date: Date, activity: ActivityType) {
        let engine = tileEngine
        var newIDs: [String] = []
        for id in ids where sessionVisitedTileIDs.insert(id).inserted {
            newIDs.append(id)
        }
        guard !newIDs.isEmpty else { return }

        for id in newIDs where sessionTiles[id] == nil {
            sessionTiles[id] = store.tiles[id]
        }

        let progress = progression.processVisits(
            tileIDs: newIDs,
            tiles: &sessionTiles,
            tileEngine: engine,
            at: date,
            activity: activity
        )

        sessionProgress.tilesVisited = sessionVisitedTileIDs.count
        sessionProgress.tilesDiscovered += progress.tilesDiscovered
        sessionProgress.tilesRevisited += progress.tilesRevisited
        sessionProgress.discoveryXP += progress.discoveryXP
        sessionProgress.familiarityXP += progress.familiarityXP
        sessionDiscoveredCount = sessionProgress.tilesDiscovered

        if progress.tilesDiscovered > 0 {
            discoveryStreak += progress.tilesDiscovered
            streakExpiresAt = date.addingTimeInterval(20 * 60)
        }

        for id in newIDs {
            if let tile = sessionTiles[id], tile.isDiscovered {
                store.upsert(tile)
            }
        }
        store.addXP(discovery: progress.discoveryXP, familiarity: progress.familiarityXP)
    }
}
