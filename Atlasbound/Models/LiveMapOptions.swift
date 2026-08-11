import SwiftUI

enum LiveMapDataLayer: String, CaseIterable, Identifiable, Sendable {
    case mastery
    case visitHeat
    case biome
    case weather

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mastery: "Mastery"
        case .visitHeat: "Visit Heat"
        case .biome: "Biomes"
        case .weather: "Weather"
        }
    }

    var symbolName: String {
        switch self {
        case .mastery: "star.hexagon.fill"
        case .visitHeat: "flame.fill"
        case .biome: "leaf.circle.fill"
        case .weather: "cloud.sun.rain.fill"
        }
    }

    var requiredLevel: Int {
        switch self {
        case .mastery: 1
        case .visitHeat: 2
        case .biome, .weather: 1
        }
    }
}
