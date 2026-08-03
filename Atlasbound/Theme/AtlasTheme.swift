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
    static let fogWashFill = Color.white.opacity(0.32)
    static let fogWashStroke = Color.white.opacity(0.20)
    static let fogWashStrokeWidth: CGFloat = 0.5

    /// Soft gold wash for undiscovered frontier neighbors (fill-only; territory stroke carries the edge).
    static let frontierWashFill = Color(red: 0.95, green: 0.75, blue: 0.20).opacity(0.10)

    /// Claimed sector boundary wash — cooler teal so it reads apart from Frontier gold.
    static let claimedTerritoryWashFill = Color(red: 0.35, green: 0.78, blue: 0.72).opacity(0.14)
    static let claimedTerritoryStroke = Color(red: 0.22, green: 0.62, blue: 0.58).opacity(0.72)
    static let claimedTerritoryStrokeWidth: CGFloat = 1.4

    /// Home Base marker / wash accent.
    static let homeBaseAccent = Color(red: 0.92, green: 0.42, blue: 0.28)

    /// Expedition target sector outline — kept thinner than territory perimeter strokes.
    static let targetBoundaryStroke = Color(red: 0.20, green: 0.48, blue: 0.98).opacity(0.78)
    static let targetBoundaryStrokeWidth: CGFloat = 1.7

    /// Cap for places-visited pins when layers are enabled.
    static let maxVisiblePlacePins = 12

    /// Cooler blue-slate for surveyed tiles (distinct from teal explored).
    static let surveyedBlue = Color(red: 0.36, green: 0.48, blue: 0.76)
    /// Richer amber for legendary tiles (distinct from mastered gold).
    static let legendaryAmber = Color(red: 1.0, green: 0.62, blue: 0.10)

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

    /// Compact spacing scale for shared chrome (section stacks, empty states, metric rows).
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

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
