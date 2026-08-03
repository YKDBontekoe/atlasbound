import Foundation
import MapKit

/// Zoom-aware draw policy for discovery / stats hex overlays.
enum MapTileLOD: Int, Sendable, Comparable {
    /// Recording / idle spans — full fills, dual rim, mastery markers.
    case near = 0
    /// Neighborhood — softer fills, single silhouette stroke.
    case mid = 1
    /// City+ — perimeter-biased outline, no markers, thinner fog.
    case far = 2

    static func < (lhs: MapTileLOD, rhs: MapTileLOD) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Approximate north–south span of the visible region in meters.
    static func spanMeters(for region: MKCoordinateRegion) -> Double {
        region.span.latitudeDelta * 111_320
    }

    /// Classify camera region. Thresholds sit above idle follow span (~950 m)
    /// so typical play stays in `.near`.
    static func resolve(for region: MKCoordinateRegion?) -> MapTileLOD {
        guard let region else { return .near }
        let meters = spanMeters(for: region)
        if meters <= nearSpanMeters {
            return .near
        }
        if meters <= midSpanMeters {
            return .mid
        }
        return .far
    }

    /// Soft-cap for discovered polygons at this LOD (never above global max).
    var polygonCap: Int {
        switch self {
        case .near: AtlasTheme.maxVisiblePolygons
        case .mid: min(240, AtlasTheme.maxVisiblePolygons)
        case .far: min(160, AtlasTheme.maxVisiblePolygons)
        }
    }

    /// Soft-cap for local fog wash hexes.
    var fogCap: Int {
        switch self {
        case .near: AtlasTheme.maxFogPolygons
        case .mid: min(80, AtlasTheme.maxFogPolygons)
        case .far: min(40, AtlasTheme.maxFogPolygons)
        }
    }

    /// Soft-cap for mastery marker annotations.
    var markerCap: Int {
        switch self {
        case .near: AtlasTheme.maxVisibleMarkers
        case .mid: min(12, AtlasTheme.maxVisibleMarkers)
        case .far: 0
        }
    }

    /// Whether fill washes are drawn for interior (non-perimeter) tiles.
    var drawsInteriorFills: Bool {
        self != .far
    }

    /// Dual brand + light inner rim on perimeter tiles.
    var drawsDualRim: Bool {
        self == .near
    }

    /// Mastery markers: all ranks with symbols (near), mastered+ only (mid), none (far).
    var minimumMarkerState: TileState? {
        switch self {
        case .near: .explored
        case .mid: .mastered
        case .far: nil
        }
    }

    /// Fill opacity multiplier applied after material base (mid softens; far unused for interiors).
    var fillOpacityScale: Double {
        switch self {
        case .near: 1.0
        case .mid: 0.82
        case .far: 0.55
        }
    }

    /// Outer rim width multiplier (charge still adds separately).
    var outerStrokeScale: CGFloat {
        switch self {
        case .near: 1.0
        case .mid: 0.92
        case .far: 0.85
        }
    }

    // MARK: - Thresholds (meters of latitude span)

    /// Just above idle follow (~950 m) so recenter stays near.
    static let nearSpanMeters: Double = 1_400
    /// Neighborhood / small city fragment.
    static let midSpanMeters: Double = 6_000
}
