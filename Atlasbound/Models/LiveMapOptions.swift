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

enum LiveMapStyle: String, CaseIterable, Identifiable, Sendable {
    case explorer
    case satellite
    case hybrid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .explorer: "Explorer"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var detail: String {
        switch self {
        case .explorer: "Clean streets and terrain"
        case .satellite: "Unlabelled aerial imagery"
        case .hybrid: "Aerial imagery with labels"
        }
    }

    var symbolName: String {
        switch self {
        case .explorer: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "map.fill"
        }
    }

    var requiredLevel: Int {
        switch self {
        case .explorer: 1
        case .satellite: 3
        case .hybrid: 5
        }
    }

}
