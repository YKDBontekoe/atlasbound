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

    /// Fog hex wash under discovered fills (light so basemap labels stay readable).
    static let fogWashFill = Color.white.opacity(0.26)
    static let fogWashStroke = Color.white.opacity(0.18)
    static let fogWashStrokeWidth: CGFloat = 0.5

    /// Soft gold wash for undiscovered frontier neighbors (fill-only; territory stroke carries the edge).
    static let frontierWashFill = Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.10)

    /// Magenta-coral accent for world events (distinct from frontier gold / expedition blue).
    static let eventAccent = Color(red: 0.86, green: 0.32, blue: 0.48)
    static let eventWashFill = Color(red: 0.86, green: 0.32, blue: 0.48).opacity(0.12)
    static let eventBoundaryStroke = Color(red: 0.86, green: 0.32, blue: 0.48).opacity(0.82)
    static let eventBoundaryStrokeWidth: CGFloat = 1.7

    /// Expedition target sector outline — kept thinner than territory perimeter strokes.
    static let targetBoundaryStroke = Color(red: 0.20, green: 0.48, blue: 0.98).opacity(0.78)
    static let targetBoundaryStrokeWidth: CGFloat = 1.7

    /// Cap for daily hotspot annotations on the discovery map.
    static let maxVisibleHotspots = 8
    /// Cap for places-visited pins when layers are enabled.
    static let maxVisiblePlacePins = 12

    /// Cooler blue-slate for surveyed tiles (distinct from teal explored).
    static let surveyedBlue = Color(red: 0.40, green: 0.52, blue: 0.74)
    /// Richer amber for legendary tiles (distinct from mastered gold).
    static let legendaryAmber = Color(red: 0.98, green: 0.68, blue: 0.12)

    static let routeOutline = Color.white.opacity(0.9)
    static let routeOutlineWidth: CGFloat = 7
    static let routeLineWidth: CGFloat = 4

    /// Soft-cap for discovered MapPolygon overlays inside the viewport.
    static let maxVisiblePolygons = 320
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

    /// Map camera meters when following the user during a recording.
    static let mapSpanRecordingMeters: Double = 650
    /// Map camera meters when idle / recentering outside a session.
    static let mapSpanIdleMeters: Double = 950

    // MARK: - Adaptive chrome (map tile accents stay brand-fixed)

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.11, green: 0.12, blue: 0.14)
            : canvas
    }

    static func chromeFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.18, green: 0.19, blue: 0.22)
            : Color.white
    }

    static func chromeStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.14)
            : Color.black.opacity(0.06)
    }

    static func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.08)
    }

    static func headerFade(for scheme: ColorScheme) -> [Color] {
        scheme == .dark
            ? [Color.black.opacity(0.72), Color.black.opacity(0)]
            : [Color.white.opacity(0.95), Color.white.opacity(0)]
    }

    static func tabBarBackground(for scheme: ColorScheme) -> Color {
        chromeFill(for: scheme)
    }

    static func cardShadow(for scheme: ColorScheme) -> Color {
        Color.black.opacity(scheme == .dark ? 0.4 : 0.08)
    }
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

    /// Distinct hue for stats map activity layer.
    var statsMapColor: Color {
        switch self {
        case .walk: AtlasTheme.teal
        case .run: Color(red: 0.25, green: 0.72, blue: 0.55)
        case .cycle: AtlasTheme.blue
        case .hike: Color(red: 0.55, green: 0.45, blue: 0.82)
        case .drive: AtlasTheme.slate
        case .publicTransport: Color(red: 0.92, green: 0.55, blue: 0.22)
        case .unknown: Color.secondary
        }
    }

    var startButtonTitle: String {
        "Start \(displayName)"
    }
}

extension TileState {
    /// Brand hue for map fills/strokes (separate from alpha so charge can boost opacity safely).
    var mapBrandColor: Color {
        switch self {
        case .fogged:
            return Color.white
        case .discovered, .explored:
            return AtlasTheme.teal
        case .surveyed:
            return AtlasTheme.surveyedBlue
        case .mastered:
            return AtlasTheme.gold
        case .legendary:
            return AtlasTheme.legendaryAmber
        }
    }

    /// Soft interior washes — keep the basemap readable; mastery ladder still steps up clearly.
    func mapFillOpacity(isFreshDiscovery: Bool = false) -> Double {
        let base: Double
        switch self {
        case .fogged:
            base = 0.55
        case .discovered:
            base = 0.18
        case .explored:
            base = 0.30
        case .surveyed:
            base = 0.36
        case .mastered:
            base = 0.42
        case .legendary:
            base = 0.56
        }
        guard isFreshDiscovery else { return base }
        switch self {
        case .discovered:
            return 0.40
        case .explored:
            return 0.48
        default:
            return min(0.72, base + 0.08)
        }
    }

    /// Weekly charge raises opacity toward more solid; never multiplies an already-transparent fill down.
    func mapFillOpacity(isFreshDiscovery: Bool, weeklyCharge: Int) -> Double {
        let base = mapFillOpacity(isFreshDiscovery: isFreshDiscovery)
        guard weeklyCharge > 0 else { return base }
        let intensity = Double(min(FrontierConstants.maxWeeklyCharge, weeklyCharge))
        return min(0.72, base + intensity * 0.07)
    }

    var mapFill: Color {
        mapBrandColor.opacity(mapFillOpacity())
    }

    var mapStroke: Color {
        switch self {
        case .fogged:
            return Color.white.opacity(0.28)
        case .discovered:
            return AtlasTheme.teal.opacity(0.78)
        case .explored:
            return AtlasTheme.teal.opacity(0.92)
        case .surveyed:
            return AtlasTheme.surveyedBlue.opacity(0.95)
        case .mastered:
            return AtlasTheme.gold.opacity(0.95)
        case .legendary:
            return AtlasTheme.legendaryAmber
        }
    }

    /// Default stroke width when drawing a full per-hex grid (stats layers, etc.).
    var mapStrokeWidth: CGFloat {
        switch self {
        case .fogged:
            return 0.6
        case .discovered:
            return 0.9
        case .explored:
            return 1.1
        case .surveyed:
            return 1.3
        case .mastered:
            return 1.7
        case .legendary:
            return 2.1
        }
    }

    /// Territory-silhouette stroke: interior hexes stay fill-only; perimeter carries the outline.
    var mapPerimeterStrokeWidth: CGFloat {
        switch self {
        case .fogged:
            return 0
        case .discovered:
            return 1.5
        case .explored:
            return 1.7
        case .surveyed:
            return 1.9
        case .mastered:
            return 2.2
        case .legendary:
            return 2.6
        }
    }

    /// Brighter fill for tiles first discovered in the active session.
    var mapFillFresh: Color {
        mapBrandColor.opacity(mapFillOpacity(isFreshDiscovery: true))
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
        mapBrandColor.opacity(mapFillOpacity(isFreshDiscovery: isFreshDiscovery))
    }

    func mapFill(isFreshDiscovery: Bool, weeklyCharge: Int) -> Color {
        mapBrandColor.opacity(mapFillOpacity(isFreshDiscovery: isFreshDiscovery, weeklyCharge: weeklyCharge))
    }

    func mapStroke(isFreshDiscovery: Bool) -> Color {
        isFreshDiscovery ? mapStrokeFresh : mapStroke
    }

    func mapStrokeWidth(isFreshDiscovery: Bool) -> CGFloat {
        isFreshDiscovery ? max(mapStrokeWidth, 1.6) : mapStrokeWidth
    }

    /// Discovery-map silhouette: only the outer rim of connected territory is stroked.
    func mapStroke(isFreshDiscovery: Bool, isPerimeter: Bool) -> Color {
        if isPerimeter {
            return mapStroke(isFreshDiscovery: isFreshDiscovery)
        }
        // Fresh interior tiles get a hairline so session discoveries still pop without grid noise.
        if isFreshDiscovery {
            return mapStrokeFresh.opacity(0.55)
        }
        return .clear
    }

    func mapStrokeWidth(isFreshDiscovery: Bool, isPerimeter: Bool) -> CGFloat {
        if isPerimeter {
            let width = mapPerimeterStrokeWidth
            return isFreshDiscovery ? max(width, 2.0) : width
        }
        return isFreshDiscovery ? 0.9 : 0
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
            return AtlasTheme.surveyedBlue
        case .mastered:
            return AtlasTheme.gold.opacity(0.92)
        case .legendary:
            return AtlasTheme.legendaryAmber
        }
    }
}

extension ExpeditionDifficulty {
    var tint: Color {
        switch self {
        case .scout: AtlasTheme.teal
        case .trailblazer: AtlasTheme.blue
        case .pathfinder: AtlasTheme.gold
        }
    }
}

enum PinpointScoreStyle {
    static func color(for score: Int) -> Color {
        if score >= 4500 { return AtlasTheme.gold }
        if score >= 3000 { return AtlasTheme.teal }
        if score >= 1000 { return AtlasTheme.blue }
        return AtlasTheme.finishRed
    }
}
