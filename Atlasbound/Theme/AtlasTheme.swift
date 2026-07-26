import SwiftUI

enum AtlasTheme {
    /// Primary action / route / timer blue from the mockups.
    static let blue = Color(red: 0.20, green: 0.48, blue: 0.98)
    /// Revealed tile mint / teal.
    static let teal = Color(red: 0.35, green: 0.78, blue: 0.72)
    /// Mastered / legendary gold.
    static let gold = Color(red: 0.95, green: 0.75, blue: 0.20)
    /// Surveyed / cooler tile fill.
    static let slate = Color(red: 0.55, green: 0.62, blue: 0.70)
    /// Finish / destructive.
    static let finishRed = Color(red: 0.92, green: 0.30, blue: 0.30)
    /// Soft page background behind cards.
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.98)
    /// Fog wash over unexplored map.
    static let fog = Color.white.opacity(0.55)

    static let cardRadius: CGFloat = 20
    static let pillRadius: CGFloat = 22
}

extension ActivityType {
    var displayName: String {
        switch self {
        case .walk: "Walk"
        case .run: "Run"
        case .cycle: "Cycle"
        case .hike: "Hike"
        case .drive: "Drive"
        case .publicTransport: "Transit"
        case .unknown: "Explore"
        }
    }

    var activeTitle: String {
        switch self {
        case .walk: "Walking"
        case .run: "Running"
        case .cycle: "Cycling"
        case .hike: "Hiking"
        case .drive: "Driving"
        case .publicTransport: "Transit"
        case .unknown: "Exploring"
        }
    }

    var symbolName: String {
        switch self {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "bicycle"
        case .hike: "figure.hiking"
        case .drive: "car.fill"
        case .publicTransport: "bus.fill"
        case .unknown: "location.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .walk: "Record tiles as you explore"
        case .run: "Reveal tiles at a faster pace"
        case .cycle: "Cover more ground efficiently"
        case .hike: "Explore trails and elevation"
        case .drive: "Discover roads passively"
        case .publicTransport: "Collect routes while you ride"
        case .unknown: "Record tiles as you explore"
        }
    }
}

extension TileState {
    var mapFill: Color {
        switch self {
        case .fogged:
            return AtlasTheme.fog
        case .discovered, .explored:
            return AtlasTheme.teal.opacity(0.45)
        case .surveyed:
            return AtlasTheme.slate.opacity(0.40)
        case .mastered, .legendary:
            return AtlasTheme.gold.opacity(0.50)
        }
    }

    var mapStroke: Color {
        switch self {
        case .fogged:
            return Color.white.opacity(0.35)
        case .discovered, .explored:
            return AtlasTheme.teal.opacity(0.85)
        case .surveyed:
            return AtlasTheme.slate.opacity(0.9)
        case .mastered, .legendary:
            return AtlasTheme.gold
        }
    }

    var markerSymbol: String? {
        switch self {
        case .fogged:
            return nil
        case .discovered, .explored:
            return "tree.fill"
        case .surveyed:
            return "mountain.2.fill"
        case .mastered, .legendary:
            return "crown.fill"
        }
    }

    var markerTint: Color {
        switch self {
        case .fogged:
            return .clear
        case .discovered, .explored:
            return AtlasTheme.teal
        case .surveyed:
            return AtlasTheme.slate
        case .mastered, .legendary:
            return AtlasTheme.gold
        }
    }
}
