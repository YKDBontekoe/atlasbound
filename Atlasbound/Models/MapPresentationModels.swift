import Foundation

/// A short-lived visual celebration emitted when the player reveals a new hex.
/// Geometry remains derived by the map from `tileID`.
struct DiscoveryMoment: Identifiable, Sendable, Equatable {
    let id: UUID
    let tileID: String
    let createdAt: Date

    init(id: UUID = UUID(), tileID: String, createdAt: Date = .now) {
        self.id = id
        self.tileID = tileID
        self.createdAt = createdAt
    }
}

/// A deliberate, player-friendly camera beat. These are reserved for rare
/// moments such as claiming a sector or focusing a landmark quest; ordinary
/// GPS discovery never takes control of the camera.
struct MapCameraMoment: Identifiable, Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case landmarkQuest
        case territoryClaim

        var zoom: Double {
            switch self {
            case .landmarkQuest: 14.4
            case .territoryClaim: 13.2
            }
        }

        var pitch: Double {
            switch self {
            case .landmarkQuest: 48
            case .territoryClaim: 54
            }
        }
    }

    let id: UUID
    let kind: Kind
    let tileID: String

    init(id: UUID = UUID(), kind: Kind, tileID: String) {
        self.id = id
        self.kind = kind
        self.tileID = tileID
    }
}

enum LandmarkQuestTheme: String, Sendable, Equatable {
    case waterside
    case greenspace
    case heritage
    case city

    var title: String {
        switch self {
        case .waterside: "Trace the waterline"
        case .greenspace: "Find the green way"
        case .heritage: "Read the old stones"
        case .city: "Follow the city signal"
        }
    }

    var symbolName: String {
        switch self {
        case .waterside: "water.waves"
        case .greenspace: "leaf.fill"
        case .heritage: "building.columns.fill"
        case .city: "sparkle.magnifyingglass"
        }
    }
}

/// A live quest card derived from the active treasure landmark. It does not
/// duplicate persistence or rewards: reaching its target advances the existing
/// daily trail / weekly vault exactly once.
struct LandmarkQuest: Identifiable, Sendable, Equatable {
    let target: LandmarkTarget
    let theme: LandmarkQuestTheme
    let distanceMeters: Double

    var id: String { target.id }
    var title: String { theme.title }
    var symbolName: String { theme.symbolName }

    var distanceLabel: String {
        if distanceMeters < 1_000 {
            return "\(Int(distanceMeters.rounded())) m away"
        }
        return String(format: "%.1f km away", distanceMeters / 1_000)
    }
}
