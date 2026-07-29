import Foundation
import Combine

private struct FactorySaveFile: Codable {
    let version: Int
    let state: FactoryState
}

@MainActor
final class FactoryStore: ObservableObject {
    static let schemaVersion = 1
    private static let saveFileName = "atlasbound-factory.json"

    @Published private(set) var state: FactoryState

    private let fileURL: URL

    init(fileURL: URL? = nil, now: Date = .now) {
        self.fileURL = fileURL ?? JSONFileStore.documentsURL(fileName: Self.saveFileName)
        if let save = JSONFileStore.load(FactorySaveFile.self, from: self.fileURL),
           save.version == Self.schemaVersion {
            state = Self.sanitized(save.state)
        } else {
            state = .empty(at: now)
            persist()
        }
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

    private func persist() {
        JSONFileStore.save(
            FactorySaveFile(version: Self.schemaVersion, state: state),
            to: fileURL
        )
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
