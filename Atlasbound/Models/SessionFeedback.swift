import Foundation

/// Ephemeral session HUD event for discovery and mastery celebrations.
struct SessionFeedbackEvent: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case discovery(count: Int)
        case mastery(state: TileState)
    }

    let id: UUID
    let kind: Kind
    let createdAt: Date

    var title: String {
        switch kind {
        case .discovery(let count):
            return count == 1 ? "+1 tile" : "+\(count) tiles"
        case .mastery(let state):
            return state.displayName
        }
    }

    var subtitle: String {
        switch kind {
        case .discovery:
            return "Discovered"
        case .mastery:
            return "Mastery up"
        }
    }

    init(id: UUID = UUID(), kind: Kind, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}
