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
    @Published private(set) var territoryState: TerritoryState = .empty

    let tileSize: TileSizeOption = .twenty

    private let database: AtlasDatabase
    private let cloudRepository = CloudProgressRepository()
    private let installationID: String
    private var deferPersistence = false
    private var dirtyTileIDs: Set<String> = []
    private var progressDirty = false
    private var frontierDirty = false
    private var territoryDirty = false
    private var pendingClear = false
    private var cloudUploadTask: Task<Void, Never>?
    private var pendingCloudUpload: CloudUpload?
    private var cloudRevision: UInt64 = 0

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

    /// True when this installation has guest or account progress worth protecting
    /// before switching to a different cloud account.
    var hasLocalProgress: Bool {
        discoveredTileCount > 0
            || discoveryXPTotal > 0
            || familiarityXPTotal > 0
            || activitiesCompleted > 0
    }

    func hasRemoteCloudRecord() async -> Bool {
        await cloudRepository.loadWorld()?.hasRemoteRecord == true
    }

    /// Mark the complete local atlas for the next authenticated upload. This is
    /// used when a guest explicitly chooses to keep this device's progress.
    func queueFullCloudUpload() {
        dirtyTileIDs = Set(tiles.keys)
        progressDirty = true
        frontierDirty = true
        territoryDirty = true
        pendingClear = true
        cloudRevision &+= 1
        persistToDisk(force: true)
    }

    var isDeferringPersistence: Bool { deferPersistence }

    var databaseURL: URL { database.fileURL }

    func hydrateFromCloud(isSessionActive: @escaping @MainActor () -> Bool = { true }) async -> Bool {
        guard let world = await cloudRepository.loadWorld() else { return false }
        guard isSessionActive() else { return false }
        guard world.hasRemoteRecord else { return true }
        tiles = world.tiles.reduce(into: [:]) { $0[$1.id] = $1 }
        if let progress = world.progress {
            discoveryXPTotal = progress.discoveryXPTotal
            familiarityXPTotal = progress.familiarityXPTotal
            activitiesCompleted = progress.activitiesCompleted
        }
        if let frontier = world.frontier { frontierState = frontier }
        if let territory = world.territory { territoryState = territory }
        dirtyTileIDs = []
        progressDirty = false
        frontierDirty = false
        territoryDirty = false
        pendingClear = false
        cloudRevision &+= 1
        database.replaceWorld(
            tiles: world.tiles,
            progress: world.progress ?? PersistedProgressRecord(
                discoveryXPTotal: discoveryXPTotal,
                familiarityXPTotal: familiarityXPTotal,
                activitiesCompleted: activitiesCompleted
            ),
            frontier: world.frontier ?? frontierState,
            territory: world.territory ?? territoryState
        )
        return true
    }

    func resetLocalSession() {
        tiles = [:]
        discoveryXPTotal = 0
        familiarityXPTotal = 0
        activitiesCompleted = 0
        frontierState = .empty
        territoryState = .empty
        dirtyTileIDs = []
        progressDirty = false
        frontierDirty = false
        territoryDirty = false
        pendingClear = false
        cloudUploadTask?.cancel()
        cloudUploadTask = nil
        pendingCloudUpload = nil
        cloudRevision &+= 1
        database.clearAllLocalState()
    }

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
            cloudRevision &+= 1
        }
        persistToDisk()
    }

    func addXP(discovery: Int, familiarity: Int) {
        guard discovery != 0 || familiarity != 0 else { return }
        discoveryXPTotal += discovery
        familiarityXPTotal += familiarity
        progressDirty = true
        cloudRevision &+= 1
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
        cloudRevision &+= 1
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
        cloudRevision &+= 1
        persistToDisk()
    }

    func refreshFrontierState(playerTile: TileCoordinate?) {
        updateFrontierState({ $0 }, playerTile: playerTile)
    }

    func updateTerritoryState(_ transform: (TerritoryState) -> TerritoryState) {
        let next = transform(territoryState)
        guard next != territoryState else { return }
        territoryState = next
        territoryDirty = true
        cloudRevision &+= 1
        persistToDisk()
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
        territoryState = .empty
        dirtyTileIDs = []
        progressDirty = true
        frontierDirty = true
        territoryDirty = true
        pendingClear = true
        cloudRevision &+= 1
        persistToDisk(force: true)
    }

    func setDeferPersistence(_ shouldDefer: Bool, flush: Bool = true) {
        if deferPersistence && !shouldDefer && flush {
            flushToDiskIfNeeded()
        }
        deferPersistence = shouldDefer
    }

    func flushToDiskIfNeeded() {
        guard pendingClear || progressDirty || frontierDirty || territoryDirty || !dirtyTileIDs.isEmpty else {
            return
        }
        writeSaveToDisk()
    }

    private func markTilesDirty(_ ids: [String]) {
        dirtyTileIDs.formUnion(ids)
        if !ids.isEmpty { cloudRevision &+= 1 }
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
        territoryState = world.territory
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
        let territory = territoryDirty ? territoryState : nil
        let cloudProgress = progress
        let cloudClear = pendingClear
        let cloudFrontier = (frontierDirty || territoryDirty) ? frontierState : nil
        let cloudTerritory = (frontierDirty || territoryDirty) ? territoryState : nil

        if pendingClear {
            database.clearWorld()
            // Re-apply any tiles that were upserted after clear in the same flush window.
            if !dirtyTiles.isEmpty {
                database.upsertTiles(dirtyTiles)
            }
            if let progress { database.saveProgress(progress) }
            if let frontier { database.saveFrontier(frontier) }
            if let territory { database.saveTerritory(territory) }
        } else {
            database.persistWorldSnapshot(
                dirtyTiles: dirtyTiles,
                progress: progress,
                frontier: frontier,
                territory: territory
            )
        }

        enqueueCloudUpload(CloudUpload(
            tiles: dirtyTiles,
            progress: cloudProgress,
            clearAllTiles: cloudClear,
            frontier: cloudFrontier,
            territory: cloudTerritory,
            revision: cloudRevision
        ))
    }

    private func enqueueCloudUpload(_ upload: CloudUpload) {
        pendingCloudUpload = upload
        guard cloudUploadTask == nil else { return }
        cloudUploadTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let next = self.pendingCloudUpload else { break }
                self.pendingCloudUpload = nil
                let succeeded = await self.cloudRepository.persist(
                    tiles: next.tiles,
                    progress: next.progress,
                    clearAllTiles: next.clearAllTiles,
                    frontier: next.frontier,
                    territory: next.territory
                )
                if succeeded {
                    if self.cloudRevision == next.revision {
                        self.dirtyTileIDs = []
                        self.progressDirty = false
                        self.frontierDirty = false
                        self.territoryDirty = false
                        self.pendingClear = false
                    }
                } else if self.pendingCloudUpload == nil {
                    self.pendingCloudUpload = next
                }
                if !succeeded {
                    try? await Task.sleep(for: .seconds(10))
                }
            }
            self?.cloudUploadTask = nil
        }
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

#if DEBUG
extension TileStore {
    /// Seeds canonical, fully mastered tiles for simulator and UI verification only.
    func debugUnlockAtlas(around center: TileCoordinate, radius: Int = 8, date: Date = .now) {
        let unlocked = tileEngine.ring(around: center, radius: radius).map { coordinate in
            WorldTile(
                id: TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: tileEngine.tileSizeMeters),
                coordinate: coordinate,
                state: .legendary,
                masteryXP: 500,
                visitCount: 12,
                uniqueVisitDays: 7,
                activityStamps: [.walk, .hike],
                firstVisitedAt: date,
                lastVisitedAt: date,
                weeklyCharge: 0,
                regionIDs: []
            )
        }
        upsertMany(unlocked)
        addXP(discovery: unlocked.count * 100, familiarity: unlocked.count * 400)
    }

    func debugGrantExplorerLevel(_ level: Int) {
        let target = ExplorerProgressionEngine().xpRequired(forLevel: max(1, level))
        let current = discoveryXPTotal + familiarityXPTotal
        addXP(discovery: max(0, target - current), familiarity: 0)
    }
}
#endif

@MainActor
private struct CloudUpload {
    let tiles: [WorldTile]
    let progress: PersistedProgressRecord?
    let clearAllTiles: Bool
    let frontier: FrontierState?
    let territory: TerritoryState?
    let revision: UInt64
}
