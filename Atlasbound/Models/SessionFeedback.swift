import Foundation

/// Ephemeral session HUD event for discovery / mastery / world-event celebration.
struct SessionFeedbackEvent: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case discovery(count: Int)
        case mastery(state: TileState)
        case worldEvent(title: String, detail: String)
        case hotspot
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
        case .worldEvent(let title, _):
            return title
        case .hotspot:
            return "Hotspot"
        }
    }

    var subtitle: String {
        switch kind {
        case .discovery:
            return "Discovered"
        case .mastery:
            return "Mastery up"
        case .worldEvent(_, let detail):
            return detail
        case .hotspot:
            return "Highlight visited"
        }
    }

    init(id: UUID = UUID(), kind: Kind, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
    }
}
