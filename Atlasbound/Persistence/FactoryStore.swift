import Foundation
import Combine

@MainActor
final class FactoryStore: ObservableObject {
    static let schemaVersion = 1

    @Published private(set) var state: FactoryState

    private let database: AtlasDatabase

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil, now: Date = .now) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }

        if let loaded = self.database.loadFactoryState() {
            state = Self.sanitized(loaded)
        } else {
            state = .empty(at: now)
            // Persist empty only when this DB has no factory row yet.
            self.database.saveFactoryState(state)
        }
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    var structures: [String: PlacedFactoryStructure] { state.structures }
    var unlockedResearchIDs: Set<String> { state.unlockedResearchIDs }
    var lifetimeProduced: [String: Int] { state.lifetimeProduced }

    func replaceState(_ next: FactoryState) {
        guard next != state else { return }
        state = next
        persist()
    }

    func update(_ transform: (inout FactoryState) -> Void) {
        var next = state
        transform(&next)
        replaceState(next)
    }

    func clear(at date: Date = .now) {
        state = .empty(at: date)
        persist()
    }

    func resetLocalSession() {
        state = .empty(at: .now)
    }

    private func persist() {
        database.saveFactoryState(state)
    }

    private static func sanitized(_ state: FactoryState) -> FactoryState {
        let tileEngine = TileEngine(option: .twenty)
        let validResearchIDs = Set(FactoryResearchCatalog.all.map(\.id))
        var next = state
        next.structures = state.structures.reduce(into: [:]) { output, entry in
            let (key, value) = entry
            guard key == value.tileID,
                  tileEngine.parseTileID(value.tileID) != nil,
                  let definition = FactoryCatalog.byID[value.definitionID] else { return }
            var structure = value
            if let roadTier = definition.roadTier {
                structure.tier = roadTier.rawValue
            } else if definition.kind == .extractor || definition.kind == .generator {
                structure.tier = max(1, min(2, structure.tier))
            } else {
                structure.tier = 1
            }
            structure.inputBuffer = sanitizedBuffer(structure.inputBuffer)
            structure.outputBuffer = sanitizedBuffer(structure.outputBuffer)
            structure.recipeProgressMinutes = max(0, structure.recipeProgressMinutes)
            structure.extractedUnits = max(0, structure.extractedUnits)
            structure.fueledMinutes = max(0, structure.fueledMinutes)
            if let recipeID = structure.selectedRecipeID,
               !definition.allowedRecipeIDs.contains(recipeID) {
                structure.selectedRecipeID = nil
                structure.recipeProgressMinutes = 0
            }
            output[key] = structure
        }
        next.unlockedResearchIDs = state.unlockedResearchIDs.intersection(validResearchIDs)
        next.unlockedResearchIDs.insert("foundations")
        next.lifetimeProduced = sanitizedBuffer(state.lifetimeProduced)
        return next
    }

    private static func sanitizedBuffer(_ buffer: [String: Int]) -> [String: Int] {
        buffer.reduce(into: [:]) { output, entry in
            guard entry.value > 0, ItemCatalog.definition(for: entry.key) != nil else { return }
            output[entry.key] = entry.value
        }
    }
}
