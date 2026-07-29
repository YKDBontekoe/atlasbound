import Foundation
import Combine

/// Loads and saves the single canonical 20 m atlas.
@MainActor
final class TileStore: ObservableObject {
    @Published private(set) var tiles: [String: WorldTile] = [:]
    @Published private(set) var discoveryXPTotal = 0
    @Published private(set) var familiarityXPTotal = 0
    @Published private(set) var activitiesCompleted = 0
    @Published private(set) var frontierState: FrontierState = .empty

    let tileSize: TileSizeOption = .twenty

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
        Set(tiles.values.lazy.filter(\.isDiscovered).map(\.id))
    }

    var discoveredTileCount: Int {
        tiles.values.lazy.filter(\.isDiscovered).count
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

        loadFromDisk()
    }

    func upsert(_ tile: WorldTile) {
        upsertMany([tile])
    }

    func upsertMany(_ newTiles: [WorldTile]) {
        guard !newTiles.isEmpty else { return }
        var next = tiles
        for tile in newTiles where isCanonical(tile) {
            next[tile.id] = tile
        }
        guard next != tiles else { return }
        tiles = next
        persistToDisk()
    }

    func applySessionProgress(
        _ progress: SessionProgress,
        updatedTiles: [String: WorldTile],
        countsAsActivity: Bool = true
    ) {
        if !updatedTiles.isEmpty {
            var next = tiles
            for (_, tile) in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
            }
            tiles = next
        }
        if countsAsActivity {
            activitiesCompleted += 1
        }
        persistToDisk()
    }

    func addXP(discovery: Int, familiarity: Int) {
        guard discovery != 0 || familiarity != 0 else { return }
        discoveryXPTotal += discovery
        familiarityXPTotal += familiarity
        persistToDisk()
    }

    func applyLiveVisitProgress(updatedTiles: [WorldTile], discoveryXP: Int, familiarityXP: Int) {
        guard !updatedTiles.isEmpty || discoveryXP != 0 || familiarityXP != 0 else { return }
        if !updatedTiles.isEmpty {
            var next = tiles
            for tile in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
            }
            tiles = next
        }
        discoveryXPTotal += discoveryXP
        familiarityXPTotal += familiarityXP
        persistToDisk()
    }

    func updateFrontierState(
        _ transform: (FrontierState) -> FrontierState,
        playerTile: TileCoordinate?,
        updatedTiles: [WorldTile] = []
    ) {
        if !updatedTiles.isEmpty {
            var next = tiles
            for tile in updatedTiles where isCanonical(tile) {
                next[tile.id] = tile
            }
            tiles = next
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
        persistToDisk()
    }

    func refreshFrontierState(playerTile: TileCoordinate?) {
        updateFrontierState({ $0 }, playerTile: playerTile)
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
        persistToDisk(force: true)
    }

    func setDeferPersistence(_ shouldDefer: Bool, flush: Bool = true) {
        if deferPersistence && !shouldDefer && flush {
            flushToDiskIfNeeded()
        }
        deferPersistence = shouldDefer
    }

    func flushToDiskIfNeeded() {
        guard persistenceDirty else { return }
        persistenceDirty = false
        writeSaveToDisk()
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        guard let save = JSONFileStore.load(WorldSaveFile.self, from: fileURL),
              save.version == JSONFileStore.currentSchemaVersion else {
            writeSaveToDisk()
            return
        }

        tiles = save.tiles.reduce(into: [:]) { result, record in
            let tile = record.asWorldTile()
            guard isCanonical(tile) else { return }
            result[tile.id] = tile
        }
        discoveryXPTotal = save.progress.discoveryXPTotal
        familiarityXPTotal = save.progress.familiarityXPTotal
        activitiesCompleted = save.progress.activitiesCompleted
        frontierState = save.frontier.asFrontierState()
    }

    private func persistToDisk(force: Bool = false) {
        if deferPersistence && !force {
            persistenceDirty = true
            return
        }
        persistenceDirty = false
        writeSaveToDisk()
    }

    private func writeSaveToDisk() {
        let save = WorldSaveFile(
            tiles: discoveredTiles.map(PersistedTileRecord.init),
            progress: PersistedProgressRecord(
                discoveryXPTotal: discoveryXPTotal,
                familiarityXPTotal: familiarityXPTotal,
                activitiesCompleted: activitiesCompleted
            ),
            frontier: PersistedFrontierRecord(from: frontierState)
        )
        JSONFileStore.save(save, to: fileURL)
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
