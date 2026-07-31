import SwiftUI

enum LiveMapDataLayer: String, CaseIterable, Identifiable, Sendable {
    case mastery
    case visitHeat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mastery: "Mastery"
        case .visitHeat: "Visit Heat"
        }
    }

    var symbolName: String {
        switch self {
        case .mastery: "star.hexagon.fill"
        case .visitHeat: "flame.fill"
        }
    }

    var requiredLevel: Int {
        switch self {
        case .mastery: 1
        case .visitHeat: 2
        }
    }
}
