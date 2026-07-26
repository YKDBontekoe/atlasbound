import Foundation
import CoreLocation
import Combine

/// Coordinates recording, tile conversion, progression, and persistence for a session.
@MainActor
final class WorldController: ObservableObject {
    @Published private(set) var liveRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var sessionVisitedTileIDs: Set<String> = []
    @Published private(set) var lastSummary: ActivitySummary?
    @Published var showSummary = false

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
    }

    var isRecording: Bool { recorder.isRecording }

    var tileEngine: TileEngine { store.tileEngine }

    func prepareLocation() {
        recorder.requestAuthorization()
    }

    func setTileSize(_ option: TileSizeOption) {
        guard !recorder.isRecording else { return }
        store.tileSize = option
        syncRecorderSettings()
    }

    func startActivity() {
        liveRoute = []
        sessionVisitedTileIDs = []
        sessionTiles = [:]
        sessionProgress = .empty
        lastSummary = nil
        recorder.start()
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

        for id in newIDs {
            if let tile = sessionTiles[id], tile.isDiscovered {
                store.upsert(tile)
            }
        }
        store.addXP(discovery: progress.discoveryXP, familiarity: progress.familiarityXP)
    }
}
