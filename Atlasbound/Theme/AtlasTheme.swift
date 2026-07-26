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
    /// Fog wash over unexplored map / fogged state fill.
    static let fog = Color.white.opacity(0.55)

    /// Fog hex wash under discovered fills (lighter so teal reads through).
    static let fogWashFill = Color.white.opacity(0.38)
    static let fogWashStroke = Color.white.opacity(0.28)
    static let fogWashStrokeWidth: CGFloat = 0.6

    static let routeOutline = Color.white.opacity(0.9)
    static let routeOutlineWidth: CGFloat = 7
    static let routeLineWidth: CGFloat = 4

    /// Soft-cap for discovered MapPolygon overlays inside the viewport.
    static let maxVisiblePolygons = 140
    /// Soft-cap for nearby fog wash hexes (MapKit struggles above ~200 polygons).
    static let maxFogPolygons = 120
    /// Cap for mastery marker annotations among visible tiles.
    static let maxVisibleMarkers = 40
    /// Extra span fraction so pans don’t pop tiles at the edge.
    static let viewportPaddingFraction = 0.12
    /// Local fog ring around the player (not full-viewport fill).
    static let fogRadiusIdle = 4
    static let fogRadiusRecording = 6

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

    var startButtonTitle: String {
        "Start \(displayName)"
    }
}

extension TileState {
    var mapFill: Color {
        switch self {
        case .fogged:
            return AtlasTheme.fog
        case .discovered:
            return AtlasTheme.teal.opacity(0.32)
        case .explored:
            return AtlasTheme.teal.opacity(0.52)
        case .surveyed:
            return AtlasTheme.slate.opacity(0.42)
        case .mastered:
            return AtlasTheme.gold.opacity(0.48)
        case .legendary:
            return AtlasTheme.gold.opacity(0.68)
        }
    }

    var mapStroke: Color {
        switch self {
        case .fogged:
            return Color.white.opacity(0.35)
        case .discovered:
            return AtlasTheme.teal.opacity(0.65)
        case .explored:
            return AtlasTheme.teal.opacity(0.95)
        case .surveyed:
            return AtlasTheme.slate.opacity(0.95)
        case .mastered:
            return AtlasTheme.gold.opacity(0.9)
        case .legendary:
            return AtlasTheme.gold
        }
    }

    var mapStrokeWidth: CGFloat {
        switch self {
        case .fogged, .discovered:
            return 0.8
        case .explored, .surveyed:
            return 1.2
        case .mastered:
            return 2
        case .legendary:
            return 2.5
        }
    }

    /// Brighter fill for tiles first discovered in the active session.
    var mapFillFresh: Color {
        switch self {
        case .discovered:
            return AtlasTheme.teal.opacity(0.58)
        case .explored:
            return AtlasTheme.teal.opacity(0.68)
        default:
            return mapFill
        }
    }

    var mapStrokeFresh: Color {
        switch self {
        case .discovered, .explored:
            return AtlasTheme.teal
        default:
            return mapStroke
        }
    }

    func mapFill(isFreshDiscovery: Bool) -> Color {
        isFreshDiscovery ? mapFillFresh : mapFill
    }

    func mapStroke(isFreshDiscovery: Bool) -> Color {
        isFreshDiscovery ? mapStrokeFresh : mapStroke
    }

    func mapStrokeWidth(isFreshDiscovery: Bool) -> CGFloat {
        isFreshDiscovery ? max(mapStrokeWidth, 1.8) : mapStrokeWidth
    }

    var markerSymbol: String? {
        switch self {
        case .fogged, .discovered:
            return nil
        case .explored:
            return "tree.fill"
        case .surveyed:
            return "mountain.2.fill"
        case .mastered:
            return "crown.fill"
        case .legendary:
            return "crown.fill"
        }
    }

    var markerTint: Color {
        switch self {
        case .fogged, .discovered:
            return .clear
        case .explored:
            return AtlasTheme.teal
        case .surveyed:
            return AtlasTheme.slate
        case .mastered:
            return AtlasTheme.gold.opacity(0.92)
        case .legendary:
            return AtlasTheme.gold
        }
    }
}
