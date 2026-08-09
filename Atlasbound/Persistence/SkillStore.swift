import Foundation
import Combine

@MainActor
final class SkillStore: ObservableObject {
    static let schemaVersion = 1

    @Published private(set) var state: SkillState

    private let database: AtlasDatabase
    private let engine = SkillTreeEngine()

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }

        if let loaded = self.database.loadSkillState() {
            state = Self.sanitized(loaded)
        } else {
            state = .empty
            self.database.saveSkillState(state)
        }
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    var ranks: [String: Int] { state.ranks }

    func modifiers() -> SkillModifiers {
        engine.modifiers(for: state)
    }

    func snapshot(explorerLevel: Int) -> SkillTreeSnapshot {
        engine.snapshot(explorerLevel: explorerLevel, state: state)
    }

    @discardableResult
    func rankUp(nodeID: String, explorerLevel: Int) -> SkillRankUpResult {
        var next = state
        let result = engine.applyRankUp(nodeID: nodeID, state: &next, explorerLevel: explorerLevel)
        guard case .ranked = result.outcome else { return result }
        state = next
        persist()
        return result
    }

    func replaceState(_ next: SkillState) {
        guard next != state else { return }
        state = Self.sanitized(next)
        persist()
    }

    func clear() {
        state = .empty
        persist()
    }

    func resetLocalSession() {
        state = .empty
    }

    private func persist() {
        database.saveSkillState(state)
    }

    private static func sanitized(_ state: SkillState) -> SkillState {
        var next = SkillState.empty
        let validIDs = Set(SkillTreeCatalog.all.map(\.id))
        for (id, rank) in state.ranks where validIDs.contains(id) && rank > 0 {
            next.ranks[id] = min(rank, 10_000)
        }
        return next
    }
}
