import Foundation
import Combine

/// Loads and saves the single canonical 20 m atlas via SQLite.
@MainActor
final class TileStore: ObservableObject {
    @Published private(set) var tiles: [String: WorldTile] = [:]
    @Published private(set) var discoveryXPTotal = 0
    @Published private(set) var familiarityXPTotal = 0
    @Published private(set) var activitiesCompleted = 0
    @Published private(set) var frontierState: FrontierState = .empty

    let tileSize: TileSizeOption = .twenty

    private let database: AtlasDatabase
    private let installationID: String
    private var deferPersistence = false
    private var dirtyTileIDs: Set<String> = []
    private var progressDirty = false
    private var frontierDirty = false
    private var pendingClear = false

    private static let installationIDKey = "atlasbound.installationID"

    var tileEngine: TileEngine { TileEngine(option: tileSize) }

    var discoveredTiles: [WorldTile] {
        tiles.values
            .filter(\.isDiscovered)
            .sorted { ($0.firstVisitedAt ?? .distantPast) < ($1.firstVisitedAt ?? .distantPast) }
    }

    var discoveredTileIDs: Set<String> {
        Set(tiles.values.lazy.filter(\.isDiscovered).map(\.id))
    }

    var discoveredTileCount: Int {
        tiles.values.lazy.filter(\.isDiscovered).count
    }

    var isDeferringPersistence: Bool { deferPersistence }

    var databaseURL: URL { database.fileURL }

    /// - Parameters:
    ///   - fileURL: Optional SQLite URL. `.json` suffixes from older tests are remapped to `.sqlite`.
    ///   - database: Shared or isolated `AtlasDatabase`. When nil, uses Documents shared DB (or creates from `fileURL`).
    ///   - installationID: Stable install id for Frontier seeding.
    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, installationID: String? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }

        if let installationID {
            self.installationID = installationID
        } else if let stored = UserDefaults.standard.string(forKey: Self.installationIDKey) {
            self.installationID = stored
        } else {
            let generated = UUID().uuidString
            UserDefaults.standard.set(generated, forKey: Self.installationIDKey)
            self.installationID = generated
        }

        loadFromDisk()
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        if fileURL.pathExtension.lowercased() == "json" {
            return fileURL.deletingPathExtension().appendingPathExtension("sqlite")
        }
        return fileURL
    }

    func upsert(_ tile: WorldTile) {
        upsertMany([tile])
    }

    func upsertMany(_ newTiles: [WorldTile]) {
        guard !newTiles.isEmpty else { return }
        var next = tiles
        var changedIDs: [String] = []
        for tile in newTiles where isCanonical(tile) {
            next[tile.id] = tile
            changedIDs.append(tile.id)
        }
        guard next != tiles else { return }
        tiles = next
        markTilesDirty(changedIDs)
        persistToDisk()
    }

    func applySessionProgress(
        _ progress: SessionProgress,
        updatedTiles: [String: WorldTile],
        countsAsActivity: Bool = true
    ) {
        if !updatedTiles.isEmpty {
            var next = tiles
            var changedIDs: [String] = []
            for (_, tile) in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
                changedIDs.append(tile.id)
            }
            tiles = next
            markTilesDirty(changedIDs)
        }
        if countsAsActivity {
            activitiesCompleted += 1
            progressDirty = true
        }
        persistToDisk()
    }

    func addXP(discovery: Int, familiarity: Int) {
        guard discovery != 0 || familiarity != 0 else { return }
        discoveryXPTotal += discovery
        familiarityXPTotal += familiarity
        progressDirty = true
        persistToDisk()
    }

    func applyLiveVisitProgress(updatedTiles: [WorldTile], discoveryXP: Int, familiarityXP: Int) {
        guard !updatedTiles.isEmpty || discoveryXP != 0 || familiarityXP != 0 else { return }
        if !updatedTiles.isEmpty {
            var next = tiles
            var changedIDs: [String] = []
            for tile in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
                changedIDs.append(tile.id)
            }
            tiles = next
            markTilesDirty(changedIDs)
        }
        discoveryXPTotal += discoveryXP
        familiarityXPTotal += familiarityXP
        progressDirty = true
        persistToDisk()
    }

    func updateFrontierState(
        _ transform: (FrontierState) -> FrontierState,
        playerTile: TileCoordinate?,
        updatedTiles: [WorldTile] = []
    ) {
        if !updatedTiles.isEmpty {
            var next = tiles
            var changedIDs: [String] = []
            for tile in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
                changedIDs.append(tile.id)
            }
            tiles = next
            markTilesDirty(changedIDs)
        }
        let engine = FrontierEngine()
        var state = engine.ensureWeeklyState(
            state: frontierState,
            playerTile: playerTile,
            discoveredTileIDs: discoveredTileIDs,
            tiles: tiles,
            tileEngine: tileEngine,
            installationID: installationID
        )
        state = transform(state)
        frontierState = state
        frontierDirty = true
        persistToDisk()
    }

    func refreshFrontierState(playerTile: TileCoordinate?) {
        updateFrontierState({ $0 }, playerTile: playerTile)
    }

    func applyWeeklyChargeResetIfNeeded() {
        let weekKey = FrontierEngine.isoWeekKey()
        guard frontierState.weekKey != weekKey else { return }

        var updatedTiles = tiles
        var changedIDs: [String] = []
        for (id, var tile) in updatedTiles where tile.weeklyCharge > 0 {
            tile.weeklyCharge = 0
            updatedTiles[id] = tile
            changedIDs.append(id)
        }
        tiles = updatedTiles
        markTilesDirty(changedIDs)

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

    func clearAtlas() {
        tiles = [:]
        discoveryXPTotal = 0
        familiarityXPTotal = 0
        activitiesCompleted = 0
        frontierState = .empty
        dirtyTileIDs = []
        progressDirty = true
        frontierDirty = true
        pendingClear = true
        persistToDisk(force: true)
    }

    func setDeferPersistence(_ shouldDefer: Bool, flush: Bool = true) {
        if deferPersistence && !shouldDefer && flush {
            flushToDiskIfNeeded()
        }
        deferPersistence = shouldDefer
    }

    func flushToDiskIfNeeded() {
        guard pendingClear || progressDirty || frontierDirty || !dirtyTileIDs.isEmpty else { return }
        writeSaveToDisk()
    }

    private func markTilesDirty(_ ids: [String]) {
        dirtyTileIDs.formUnion(ids)
    }

    private func loadFromDisk() {
        let world = database.loadWorld()
        tiles = world.tiles.reduce(into: [:]) { result, entry in
            guard isCanonical(entry.value) else { return }
            result[entry.key] = entry.value
        }
        discoveryXPTotal = world.progress.discoveryXPTotal
        familiarityXPTotal = world.progress.familiarityXPTotal
        activitiesCompleted = world.progress.activitiesCompleted
        frontierState = world.frontier
    }

    private func persistToDisk(force: Bool = false) {
        if deferPersistence && !force {
            return
        }
        writeSaveToDisk()
    }

    private func writeSaveToDisk() {
        let dirtyTiles = dirtyTileIDs.compactMap { tiles[$0] }.filter(\.isDiscovered)
        let progress = progressDirty
            ? PersistedProgressRecord(
                discoveryXPTotal: discoveryXPTotal,
                familiarityXPTotal: familiarityXPTotal,
                activitiesCompleted: activitiesCompleted
              )
            : nil
        let frontier = frontierDirty ? frontierState : nil

        if pendingClear {
            database.clearWorld()
            // Re-apply any tiles that were upserted after clear in the same flush window.
            if !dirtyTiles.isEmpty {
                database.upsertTiles(dirtyTiles)
            }
            if let progress { database.saveProgress(progress) }
            if let frontier { database.saveFrontier(frontier) }
        } else {
            database.persistWorldSnapshot(
                dirtyTiles: dirtyTiles,
                progress: progress,
                frontier: frontier
            )
        }

        dirtyTileIDs = []
        progressDirty = false
        frontierDirty = false
        pendingClear = false
    }

    private func isCanonical(_ tile: WorldTile) -> Bool {
        guard tileEngine.parseTileID(tile.id) == tile.coordinate else { return false }
        return tile.id == TileEngine.makeTileID(
            q: tile.coordinate.q,
            r: tile.coordinate.r,
            sizeMeters: tileSize.meters
        )
    }
}
