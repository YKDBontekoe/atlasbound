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
    private let fileURL: URL
    private let installationID: String
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

    /// All discovered tiles grouped by grid size (60 / 80 / 100 m).
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

    init(fileURL: URL? = nil, installationID: String? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = docs.appendingPathComponent(Self.saveFileName)
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

        tileSize = ActivityType.walk.tileSize
        loadFromDisk()
        loadForCurrentTileSize()
    }

    func upsert(_ tile: WorldTile) {
        var next = tiles
        next[tile.id] = tile
        tiles = next
        allTilesBySize[tileSize.rawValue] = next
        persistToDisk()
    }

    func applySessionProgress(_ progress: SessionProgress, updatedTiles: [String: WorldTile]) {
        for (_, tile) in updatedTiles {
            upsert(tile)
        }
        activitiesCompleted += 1
        var record = progressBySize[tileSize.rawValue] ?? PersistedProgressRecord(
            discoveryXPTotal: discoveryXPTotal,
            familiarityXPTotal: familiarityXPTotal,
            activitiesCompleted: activitiesCompleted,
            tileSizeMeters: tileSize.rawValue
        )
        record.discoveryXPTotal = discoveryXPTotal
        record.familiarityXPTotal = familiarityXPTotal
        record.activitiesCompleted = activitiesCompleted
        progressBySize[tileSize.rawValue] = record
        persistToDisk()
    }

    func addXP(discovery: Int, familiarity: Int) {
        guard discovery != 0 || familiarity != 0 else { return }
        discoveryXPTotal += discovery
        familiarityXPTotal += familiarity
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
        persistToDisk()
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
        progressBySize[tileSize.rawValue] = PersistedProgressRecord(
            discoveryXPTotal: 0,
            familiarityXPTotal: 0,
            activitiesCompleted: 0,
            tileSizeMeters: tileSize.rawValue
        )
        persistToDisk()
    }

    // MARK: - Disk

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let save = try decoder.decode(WorldSaveFile.self, from: data)

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
        } catch {
            allTilesBySize = [:]
            progressBySize = [:]
            frontierBySize = [:]
        }
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
    }

    private func persistToDisk() {
        allTilesBySize[tileSize.rawValue] = tiles
        frontierBySize[tileSize.rawValue] = frontierState

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

        let save = WorldSaveFile(
            tiles: records,
            progressBySize: progressPayload,
            frontierBySize: frontierPayload.isEmpty ? nil : frontierPayload
        )
        do {
            let data = try encoder.encode(save)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep in-memory state if disk write fails.
        }
    }
}
