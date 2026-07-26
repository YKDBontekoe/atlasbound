import Foundation
import Combine

/// Loads and saves discovered tile progress as JSON in the app Documents directory.
@MainActor
final class TileStore: ObservableObject {
    @Published private(set) var tiles: [String: WorldTile] = [:]
    @Published private(set) var discoveryXPTotal: Int = 0
    @Published private(set) var familiarityXPTotal: Int = 0
    @Published private(set) var activitiesCompleted: Int = 0
    @Published var tileSize: TileSizeOption = .default {
        didSet {
            if oldValue != tileSize {
                UserDefaults.standard.set(tileSize.rawValue, forKey: Self.tileSizeKey)
                loadForCurrentTileSize()
            }
        }
    }

    private var allTilesBySize: [Int: [String: WorldTile]] = [:]
    private var progressBySize: [Int: PersistedProgressRecord] = [:]
    private let fileURL: URL
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

    private static let tileSizeKey = "atlasbound.tileSizeMeters"
    private static let saveFileName = "atlasbound-world.json"

    var tileEngine: TileEngine { TileEngine(option: tileSize) }

    var discoveredTiles: [WorldTile] {
        tiles.values
            .filter(\.isDiscovered)
            .sorted { ($0.firstVisitedAt ?? .distantPast) < ($1.firstVisitedAt ?? .distantPast) }
    }

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = docs.appendingPathComponent(Self.saveFileName)
        }

        if let stored = UserDefaults.standard.object(forKey: Self.tileSizeKey) as? Int,
           let option = TileSizeOption(rawValue: stored) {
            self.tileSize = option
        }

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

    func clearCurrentGrid() {
        tiles = [:]
        allTilesBySize[tileSize.rawValue] = [:]
        discoveryXPTotal = 0
        familiarityXPTotal = 0
        activitiesCompleted = 0
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
        } catch {
            allTilesBySize = [:]
            progressBySize = [:]
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
    }

    private func persistToDisk() {
        allTilesBySize[tileSize.rawValue] = tiles

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

        let save = WorldSaveFile(tiles: records, progressBySize: progressPayload)
        do {
            let data = try encoder.encode(save)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep in-memory state if disk write fails.
        }
    }
}
