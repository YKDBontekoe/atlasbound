import SwiftUI

/// Coherent atlas “material” recipe for one hex overlay draw.
struct TileMapMaterial {
    /// Interior / silhouette wash (may be clear when outline-only).
    let fill: Color
    /// Brand rim on the territory silhouette (or fresh hairline on interiors).
    let outerStroke: Color
    let outerStrokeWidth: CGFloat
    /// Optional light inner rim — near LOD perimeter only; drawn as a second MapPolygon.
    let innerStroke: Color?
    let innerStrokeWidth: CGFloat

    var drawsDualRim: Bool { innerStroke != nil && innerStrokeWidth > 0 }

    /// Resolve fill + rim styling for mastery (and fogged) tiles.
    static func resolve(
        state: TileState,
        isFreshDiscovery: Bool = false,
        weeklyCharge: Int = 0,
        isPerimeter: Bool,
        lod: MapTileLOD = .near
    ) -> TileMapMaterial {
        let brand = state.mapBrandColor
        let charge = max(0, min(FrontierConstants.maxWeeklyCharge, weeklyCharge))
        let fillOpacity = state.mapFillOpacity(isFreshDiscovery: isFreshDiscovery, weeklyCharge: charge)
            * lod.fillOpacityScale
        let fill: Color = {
            if lod == .far {
                // Outline-forward silhouette — keep a whisper wash so the rim reads as territory.
                return brand.opacity(min(0.28, fillOpacity * 0.45))
            }
            return brand.opacity(fillOpacity)
        }()

        if isPerimeter {
            let outerWidth = (
                state.mapPerimeterStrokeWidth
                    + CGFloat(charge) * 0.18
                    + (isFreshDiscovery ? 0.25 : 0)
            ) * lod.outerStrokeScale

            let outerStroke: Color = {
                if isFreshDiscovery {
                    return state.mapStrokeFresh
                }
                if charge > 0 {
                    // Charged rims read denser without adding a second overlay layer.
                    return brand.opacity(min(1, 0.78 + Double(charge) * 0.07))
                }
                return state.mapStroke
            }()

            let dual = lod.drawsDualRim && state.rawValue >= TileState.explored.rawValue
            let inner: (Color, CGFloat)? = {
                guard dual else { return nil }
                return (state.mapInnerRimColor, state.mapInnerRimWidth)
            }()

            return TileMapMaterial(
                fill: fill,
                outerStroke: outerStroke,
                outerStrokeWidth: outerWidth,
                innerStroke: inner?.0,
                innerStrokeWidth: inner?.1 ?? 0
            )
        }

        // Interiors: fill-only except a fresh hairline so session finds still pop.
        if isFreshDiscovery && lod.drawsInteriorFills {
            return TileMapMaterial(
                fill: fill,
                outerStroke: state.mapStrokeFresh.opacity(0.55),
                outerStrokeWidth: 0.95,
                innerStroke: nil,
                innerStrokeWidth: 0
            )
        }

        return TileMapMaterial(
            fill: lod.drawsInteriorFills ? fill : .clear,
            outerStroke: .clear,
            outerStrokeWidth: 0,
            innerStroke: nil,
            innerStrokeWidth: 0
        )
    }
}

// MARK: - TileState map chrome (material inputs)

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
            base = 0.20
        case .explored:
            base = 0.32
        case .surveyed:
            base = 0.40
        case .mastered:
            base = 0.48
        case .legendary:
            base = 0.60
        }
        guard isFreshDiscovery else { return base }
        switch self {
        case .discovered:
            return 0.46
        case .explored:
            return 0.54
        default:
            return min(0.72, base + 0.10)
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
            return AtlasTheme.teal.opacity(0.82)
        case .explored:
            return AtlasTheme.teal.opacity(0.94)
        case .surveyed:
            return AtlasTheme.surveyedBlue.opacity(0.96)
        case .mastered:
            return AtlasTheme.gold.opacity(0.96)
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
            return 1.6
        case .explored:
            return 1.9
        case .surveyed:
            return 2.1
        case .mastered:
            return 2.4
        case .legendary:
            return 2.8
        }
    }

    /// Light inner rim for near-LOD dual-stroke silhouette (explored+).
    var mapInnerRimColor: Color {
        switch self {
        case .fogged, .discovered:
            return .clear
        case .explored:
            return Color.white.opacity(0.42)
        case .surveyed:
            return Color.white.opacity(0.48)
        case .mastered:
            return Color.white.opacity(0.55)
        case .legendary:
            return Color.white.opacity(0.62)
        }
    }

    var mapInnerRimWidth: CGFloat {
        switch self {
        case .fogged, .discovered:
            return 0
        case .explored:
            return 0.75
        case .surveyed:
            return 0.85
        case .mastered:
            return 1.0
        case .legendary:
            return 1.15
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
        TileMapMaterial.resolve(
            state: self,
            isFreshDiscovery: isFreshDiscovery,
            isPerimeter: isPerimeter,
            lod: .near
        ).outerStroke
    }

    func mapStrokeWidth(isFreshDiscovery: Bool, isPerimeter: Bool) -> CGFloat {
        TileMapMaterial.resolve(
            state: self,
            isFreshDiscovery: isFreshDiscovery,
            isPerimeter: isPerimeter,
            lod: .near
        ).outerStrokeWidth
    }

    var markerSymbol: String? {
        switch self {
        case .fogged, .discovered:
            return nil
        case .explored:
            return "tree.fill"
        case .surveyed:
            return "mountain.2.fill"
        case .mastered, .legendary:
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

    /// Hairline stroke on mastery marker chrome.
    var markerChromeStroke: Color {
        switch self {
        case .fogged, .discovered:
            return .clear
        case .explored:
            return Color.white.opacity(0.55)
        case .surveyed:
            return Color.white.opacity(0.60)
        case .mastered:
            return Color.white.opacity(0.70)
        case .legendary:
            return Color.white.opacity(0.82)
        }
    }

    var markerSymbolWeight: Font.Weight {
        switch self {
        case .legendary:
            return .heavy
        case .mastered, .surveyed:
            return .bold
        default:
            return .semibold
        }
    }

    /// Legendary markers may ambient-pulse; lower ranks only celebrate on appear.
    var markerPulses: Bool {
        self == .legendary
    }
}
