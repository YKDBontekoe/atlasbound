import Foundation
import Combine

/// Loads and saves discovered tile progress as JSON in the app Documents directory.
@MainActor
final class TileStore: ObservableObject {
    @Published private(set) var tiles: [String: WorldTile] = [:]
    @Published private(set) var discoveryXPTotal: Int = 0
    @Published private(set) var familiarityXPTotal: Int = 0
    @Published private(set) var activitiesCompleted: Int = 0
    @Published private(set) var frontierState: FrontierState = .empty
    @Published private(set) var worldEventState: WorldEventState = .empty
    /// Active reveal grid — always driven by the current activity type, never a user preference.
    @Published var tileSize: TileSizeOption = .default {
        didSet {
            if oldValue != tileSize {
                loadForCurrentTileSize()
            }
        }
    }

    private var allTilesBySize: [Int: [String: WorldTile]] = [:]
    private var progressBySize: [Int: PersistedProgressRecord] = [:]
    private var frontierBySize: [Int: FrontierState] = [:]
    private var eventsBySize: [Int: WorldEventState] = [:]
    private let fileURL: URL
    private let installationID: String
    private var deferPersistence = false
    private var persistenceDirty = false

    private static let saveFileName = "atlasbound-world.json"
    private static let installationIDKey = "atlasbound.installationID"

    var tileEngine: TileEngine { TileEngine(option: tileSize) }

    var discoveredTiles: [WorldTile] {
        tiles.values
            .filter(\.isDiscovered)
            .sorted { ($0.firstVisitedAt ?? .distantPast) < ($1.firstVisitedAt ?? .distantPast) }
    }

    var discoveredTileIDs: Set<String> {
        Set(discoveredTiles.map(\.id))
    }

    /// All discovered tiles grouped by grid size (15 / 20 / 25 m).
    var allDiscoveredTilesBySize: [Int: [WorldTile]] {
        var result: [Int: [WorldTile]] = [:]
        for (size, map) in allTilesBySize {
            let discovered = map.values.filter(\.isDiscovered)
            if !discovered.isEmpty {
                result[size] = Array(discovered)
            }
        }
        return result
    }

    func frontierState(for size: Int) -> FrontierState {
        frontierBySize[size] ?? .empty
    }

    func worldEventState(for size: Int) -> WorldEventState {
        eventsBySize[size] ?? .empty
    }

    init(fileURL: URL? = nil, installationID: String? = nil) {
        self.fileURL = fileURL ?? JSONFileStore.documentsURL(fileName: Self.saveFileName)

        if let installationID {
            self.installationID = installationID
        } else if let stored = UserDefaults.standard.string(forKey: Self.installationIDKey) {
            self.installationID = stored
        } else {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: Self.installationIDKey)
            self.installationID = generated
        }

        tileSize = ActivityType.walk.tileSize
        loadFromDisk()
        loadForCurrentTileSize()
    }

    func upsert(_ tile: WorldTile) {
        upsertMany([tile])
    }

    /// Batch write tiles once to disk (avoids N atomic writes mid-session).
    func upsertMany(_ newTiles: [WorldTile]) {
        guard !newTiles.isEmpty else { return }
        var next = tiles
        for tile in newTiles {
            next[tile.id] = tile
        }
        tiles = next
        allTilesBySize[tileSize.rawValue] = next
        persistToDisk()
    }

    func applySessionProgress(_ progress: SessionProgress, updatedTiles: [String: WorldTile]) {
        if !updatedTiles.isEmpty {
            var next = tiles
            for (_, tile) in updatedTiles {
                next[tile.id] = tile
            }
            tiles = next
            allTilesBySize[tileSize.rawValue] = next
        }
        activitiesCompleted += 1
        syncProgressRecord()
        persistToDisk()
    }

    func addXP(discovery: Int, familiarity: Int) {
        guard discovery != 0 || familiarity != 0 else { return }
        discoveryXPTotal += discovery
        familiarityXPTotal += familiarity
        syncProgressRecord()
        persistToDisk()
    }

    /// Apply mid-session tile + XP updates with a single disk write.
    func applyLiveVisitProgress(updatedTiles: [WorldTile], discoveryXP: Int, familiarityXP: Int) {
        guard !updatedTiles.isEmpty || discoveryXP != 0 || familiarityXP != 0 else { return }
        if !updatedTiles.isEmpty {
            var next = tiles
            for tile in updatedTiles {
                next[tile.id] = tile
            }
            tiles = next
            allTilesBySize[tileSize.rawValue] = next
        }
        if discoveryXP != 0 || familiarityXP != 0 {
            discoveryXPTotal += discoveryXP
            familiarityXPTotal += familiarityXP
            syncProgressRecord()
        }
        persistToDisk()
    }

    private func syncProgressRecord() {
        var record = progressBySize[tileSize.rawValue] ?? PersistedProgressRecord(
            discoveryXPTotal: 0,
            familiarityXPTotal: 0,
            activitiesCompleted: activitiesCompleted,
            tileSizeMeters: tileSize.rawValue
        )
        record.discoveryXPTotal = discoveryXPTotal
        record.familiarityXPTotal = familiarityXPTotal
        record.activitiesCompleted = activitiesCompleted
        progressBySize[tileSize.rawValue] = record
    }

    func updateFrontierState(_ transform: (FrontierState) -> FrontierState, playerTile: TileCoordinate?) {
        let engine = FrontierEngine()
        var state = frontierState
        state = engine.ensureWeeklyState(
            state: state,
            playerTile: playerTile,
            discoveredTileIDs: discoveredTileIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: installationID
        )
        state = transform(state)
        frontierState = state
        frontierBySize[tileSize.rawValue] = state
        persistToDisk()
    }

    func refreshFrontierState(playerTile: TileCoordinate?) {
        updateFrontierState({ $0 }, playerTile: playerTile)
    }

    func updateWorldEventState(_ transform: (WorldEventState) -> WorldEventState, playerTile: TileCoordinate?) {
        let engine = WorldEventEngine()
        var state = worldEventState
        state = engine.ensureState(
            state: state,
            playerTile: playerTile,
            discoveredTileIDs: discoveredTileIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: installationID
        )
        state = transform(state)
        worldEventState = state
        eventsBySize[tileSize.rawValue] = state
        persistToDisk()
    }

    func refreshWorldEventState(playerTile: TileCoordinate?) {
        updateWorldEventState({ $0 }, playerTile: playerTile)
    }

    func applyWeeklyChargeResetIfNeeded() {
        let weekKey = FrontierEngine.isoWeekKey()
        guard frontierState.weekKey != weekKey else { return }

        var updatedTiles = tiles
        for (id, var tile) in updatedTiles where tile.weeklyCharge > 0 {
            tile.weeklyCharge = 0
            updatedTiles[id] = tile
        }
        tiles = updatedTiles
        allTilesBySize[tileSize.rawValue] = updatedTiles

        updateFrontierState({ state in
            var next = state
            if next.weeklyScore > next.bestWeekScore {
                next.bestWeekScore = next.weeklyScore
            }
            next.weekKey = weekKey
            next.offers = []
            next.activeOfferID = nil
            next.completedOfferIDs = []
            next.weeklyScore = 0
            next.connectionBonusesAwarded = []
            next.chargedTileIDs = []
            return next
        }, playerTile: nil)
    }

    func clearCurrentGrid() {
        tiles = [:]
        allTilesBySize[tileSize.rawValue] = [:]
        discoveryXPTotal = 0
        familiarityXPTotal = 0
        activitiesCompleted = 0
        frontierState = .empty
        frontierBySize[tileSize.rawValue] = .empty
        worldEventState = .empty
        eventsBySize[tileSize.rawValue] = .empty
        progressBySize[tileSize.rawValue] = PersistedProgressRecord(
            discoveryXPTotal: 0,
            familiarityXPTotal: 0,
            activitiesCompleted: 0,
            tileSizeMeters: tileSize.rawValue
        )
        persistToDisk(force: true)
    }

    /// While recording, skip atomic rewrites; memory stays authoritative until flush.
    func setDeferPersistence(_ defer: Bool, flush: Bool = true) {
        if deferPersistence && !defer && flush {
            flushToDiskIfNeeded()
        }
        deferPersistence = defer
    }

    /// Write pending changes after pause, background, or session end.
    func flushToDiskIfNeeded() {
        guard persistenceDirty else { return }
        persistenceDirty = false
        writeSaveToDisk()
    }

    // MARK: - Disk

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let save = JSONFileStore.load(WorldSaveFile.self, from: fileURL) else {
            allTilesBySize = [:]
            progressBySize = [:]
            frontierBySize = [:]
            eventsBySize = [:]
            return
        }

        var grouped: [Int: [String: WorldTile]] = [:]
        for record in save.tiles {
            var map = grouped[record.tileSizeMeters] ?? [:]
            map[record.id] = record.asWorldTile()
            grouped[record.tileSizeMeters] = map
        }
        allTilesBySize = grouped

        var progress: [Int: PersistedProgressRecord] = [:]
        for (key, value) in save.progressBySize {
            if let size = Int(key) {
                progress[size] = value
            }
        }
        progressBySize = progress

        var frontier: [Int: FrontierState] = [:]
        if let frontierPayload = save.frontierBySize {
            for (key, value) in frontierPayload {
                if let size = Int(key) {
                    frontier[size] = value.asFrontierState()
                }
            }
        }
        frontierBySize = frontier

        var events: [Int: WorldEventState] = [:]
        if let eventsPayload = save.eventsBySize {
            for (key, value) in eventsPayload {
                if let size = Int(key) {
                    events[size] = value.asWorldEventState()
                }
            }
        }
        eventsBySize = events
    }

    private func loadForCurrentTileSize() {
        let size = tileSize.rawValue
        tiles = allTilesBySize[size] ?? [:]
        if let progress = progressBySize[size] {
            discoveryXPTotal = progress.discoveryXPTotal
            familiarityXPTotal = progress.familiarityXPTotal
            activitiesCompleted = progress.activitiesCompleted
        } else {
            discoveryXPTotal = 0
            familiarityXPTotal = 0
            activitiesCompleted = 0
        }
        frontierState = frontierBySize[size] ?? .empty
        worldEventState = eventsBySize[size] ?? .empty
    }

    private func persistToDisk(force: Bool = false) {
        allTilesBySize[tileSize.rawValue] = tiles
        frontierBySize[tileSize.rawValue] = frontierState
        eventsBySize[tileSize.rawValue] = worldEventState

        if deferPersistence && !force {
            persistenceDirty = true
            return
        }
        persistenceDirty = false
        writeSaveToDisk()
    }

    private func writeSaveToDisk() {

        var records: [PersistedTileRecord] = []
        for (size, map) in allTilesBySize {
            for tile in map.values where tile.isDiscovered {
                records.append(PersistedTileRecord(from: tile, tileSizeMeters: size))
            }
        }

        var progressPayload: [String: PersistedProgressRecord] = [:]
        for (size, record) in progressBySize {
            progressPayload[String(size)] = record
        }

        var frontierPayload: [String: PersistedFrontierRecord] = [:]
        for (size, state) in frontierBySize where !state.offers.isEmpty || state.weeklyScore > 0 || state.lifetimeCompletedExpeditions > 0 {
            frontierPayload[String(size)] = PersistedFrontierRecord(from: state)
        }

        var eventsPayload: [String: PersistedWorldEventRecord] = [:]
        for (size, state) in eventsBySize where !state.dayKey.isEmpty || state.lifetimeEventsCompleted > 0 || !state.dailyHotspotTileIDs.isEmpty {
            eventsPayload[String(size)] = PersistedWorldEventRecord(from: state)
        }

        let save = WorldSaveFile(
            tiles: records,
            progressBySize: progressPayload,
            frontierBySize: frontierPayload.isEmpty ? nil : frontierPayload,
            eventsBySize: eventsPayload.isEmpty ? nil : eventsPayload
        )
        JSONFileStore.save(save, to: fileURL)
    }
}
