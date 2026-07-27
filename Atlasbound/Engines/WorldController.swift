import Foundation
import CoreLocation
import Combine

/// Coordinates recording, tile conversion, progression, and persistence for a session.
@MainActor
final class WorldController: ObservableObject {
    @Published private(set) var liveRoute: [CLLocationCoordinate2D] = []
    @Published private(set) var sessionVisitedTileIDs: Set<String> = []
    /// Tile IDs first discovered during the active session (map highlight).
    @Published private(set) var sessionDiscoveredIDs: Set<String> = []
    @Published private(set) var sessionDiscoveredCount = 0
    @Published private(set) var discoveryStreak = 0
    @Published private(set) var streakExpiresAt: Date?
    @Published private(set) var lastSummary: ActivitySummary?
    @Published var showSummary = false
    @Published var showLayers = false

    /// Soft regional label until Region Engine exists (not a real geo boundary).
    let regionName = "Dordrecht"

    let recorder: ActivityRecorder
    let store: TileStore
    let activityHistory: ActivityHistoryStore
    private let progression = ProgressionEngine()

    /// Tiles mutated during the active session (merged into store on stop).
    private var sessionTiles: [String: WorldTile] = [:]
    private var sessionProgress = SessionProgress.empty

    private static let selectedActivityKey = "atlasbound.selectedActivityType"

    init(store: TileStore, activityHistory: ActivityHistoryStore, recorder: ActivityRecorder? = nil) {
        self.store = store
        self.activityHistory = activityHistory
        self.recorder = recorder ?? ActivityRecorder()
        restoreSelectedActivityType()
        syncRecorderSettings()

        self.recorder.onSample = { [weak self] sample in
            self?.handleSample(sample)
        }
        syncTileSizeToActivity()
    }

    var isRecording: Bool { recorder.isRecording }
    var isPaused: Bool { recorder.isPaused }

    var tileEngine: TileEngine { store.tileEngine }

    /// Lifetime discovered tiles on the active grid (honest stand-in until real regions).
    var discoveredTileCount: Int { store.discoveredTiles.count }

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
        guard type != .unknown else { return }
        recorder.activityType = type
        UserDefaults.standard.set(type.rawValue, forKey: Self.selectedActivityKey)
        syncTileSizeToActivity()
    }

    private func restoreSelectedActivityType() {
        guard let raw = UserDefaults.standard.string(forKey: Self.selectedActivityKey),
              let type = ActivityType(rawValue: raw),
              type != .unknown else {
            return
        }
        recorder.activityType = type
    }

    func startActivity() {
        syncTileSizeToActivity()
        liveRoute = []
        sessionVisitedTileIDs = []
        sessionDiscoveredIDs = []
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
        activityHistory.record(summary, tileSizeMeters: store.tileSize.rawValue)
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

        let discoveryCandidates = Set(newIDs.filter { id in
            guard let tile = sessionTiles[id] else { return true }
            return tile.state == .fogged || tile.firstVisitedAt == nil
        })

        let progress = progression.processVisits(
            tileIDs: newIDs,
            tiles: &sessionTiles,
            tileEngine: engine,
            at: date,
            activity: activity
        )

        var discovered = sessionDiscoveredIDs
        for id in discoveryCandidates {
            if let tile = sessionTiles[id], tile.isDiscovered {
                discovered.insert(id)
            }
        }
        sessionDiscoveredIDs = discovered

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

#if DEBUG
extension WorldController {
    /// Default seed for Simulator testing (matches placeholder region label).
    static let debugDefaultCoordinate = CLLocationCoordinate2D(latitude: 51.8133, longitude: 4.6901)

    enum DebugStepSize: Double, CaseIterable, Identifiable {
        case fine = 25
        case tile = 55
        case leap = 120

        var id: Double { rawValue }

        var label: String {
            switch self {
            case .fine: "25 m"
            case .tile: "55 m"
            case .leap: "120 m"
            }
        }
    }

    func debugEnableSimulation(seedIfNeeded: Bool = true) {
        recorder.setSimulationActive(true)
        if seedIfNeeded, recorder.lastLocation == nil {
            debugTeleport(to: Self.debugDefaultCoordinate)
        }
    }

    func debugDisableSimulation() {
        recorder.setSimulationActive(false)
    }

    func debugTeleport(to coordinate: CLLocationCoordinate2D, course: CLLocationDirection = 0, speed: CLLocationSpeed = 0) {
        recorder.setSimulationActive(true)
        recorder.ingestSimulatedLocation(
            Self.debugLocation(coordinate: coordinate, course: course, speed: speed)
        )
    }

    /// Move relative to the current simulated position (north/east meters).
    func debugNudge(northMeters: Double, eastMeters: Double, speed: CLLocationSpeed = 1.4) {
        recorder.setSimulationActive(true)
        let base = recorder.lastLocation?.coordinate ?? Self.debugDefaultCoordinate
        let next = Self.offset(base, northMeters: northMeters, eastMeters: eastMeters)
        let course = Self.courseDegrees(northMeters: northMeters, eastMeters: eastMeters)
        recorder.ingestSimulatedLocation(
            Self.debugLocation(coordinate: next, course: course, speed: speed)
        )
    }

    func debugNudge(headingDegrees: Double, distanceMeters: Double, speed: CLLocationSpeed = 1.4) {
        let radians = headingDegrees * .pi / 180
        let north = cos(radians) * distanceMeters
        let east = sin(radians) * distanceMeters
        debugNudge(northMeters: north, eastMeters: east, speed: speed)
    }

    private static func debugLocation(
        coordinate: CLLocationCoordinate2D,
        course: CLLocationDirection,
        speed: CLLocationSpeed
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: -1,
            course: course,
            speed: max(0, speed),
            timestamp: Date()
        )
    }

    private static func offset(
        _ coordinate: CLLocationCoordinate2D,
        northMeters: Double,
        eastMeters: Double
    ) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0
        let dLat = (northMeters / earth) * (180 / .pi)
        let cosLat = cos(coordinate.latitude * .pi / 180)
        let dLon = cosLat == 0 ? 0 : (eastMeters / (earth * cosLat)) * (180 / .pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }

    private static func courseDegrees(northMeters: Double, eastMeters: Double) -> CLLocationDirection {
        guard northMeters != 0 || eastMeters != 0 else { return 0 }
        var degrees = atan2(eastMeters, northMeters) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }
}
#endif
