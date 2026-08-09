import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

enum AtlasStatsMapLayer: String, CaseIterable, Identifiable {
    case mastery, activity, discoveryAge, visitHeat, frontier
    var id: String { rawValue }
    var label: String { rawValue == "discoveryAge" ? "Age" : rawValue.capitalized }
    var iconName: String {
        switch self {
        case .mastery: "star.hexagon.fill"
        case .activity: "figure.walk"
        case .discoveryAge: "clock.arrow.circlepath"
        case .visitHeat: "flame.fill"
        case .frontier: "flag.fill"
        }
    }
}

/// Read-only layered atlas map rendered with Mapbox annotations.
struct AtlasStatsMapView: View {
    let tiles: [WorldTile]
    @Binding var layer: AtlasStatsMapLayer
    var frontierChargedTileIDs: Set<String> = []
    var interactive: Bool = true
    var height: CGFloat = 220

    @State private var viewport: Viewport = .styleDefault

    private var overlays: [StatsPolygon] {
        let engine = TileEngine(tileSizeMeters: 20)
        let visible = Array(tiles.filter(\.isDiscovered).prefix(AtlasTheme.maxVisiblePolygons))
        let maximumVisitCount = max(visible.map(\.visitCount).max() ?? 1, 1)
        let dates = visible.compactMap(\.firstVisitedAt)
        let earliest = dates.min() ?? .now
        let latest = dates.max() ?? earliest
        let dateSpan = max(latest.timeIntervalSince(earliest), 1)

        return visible.map { tile in
            let color: UIColor
            switch layer {
            case .mastery:
                color = UIColor(tile.state.mapBrandColor)
            case .activity:
                color = UIColor((StatsEngine.dominantActivity(for: tile) ?? .unknown).statsMapColor)
            case .discoveryAge:
                let age = tile.firstVisitedAt.map { latest.timeIntervalSince($0) } ?? dateSpan
                let intensity = 1 - min(1, age / dateSpan)
                color = UIColor(
                    red: 0.45 + intensity * 0.45,
                    green: 0.62 + intensity * 0.18,
                    blue: 0.78 - intensity * 0.48,
                    alpha: 1
                )
            case .visitHeat:
                let intensity = min(1, Double(tile.visitCount) / Double(maximumVisitCount))
                color = UIColor(red: 0.10, green: 0.62, blue: 0.62, alpha: 0.15 + intensity * 0.75)
            case .frontier:
                color = frontierChargedTileIDs.contains(tile.id) ? .systemYellow : .systemBlue
            }
            return StatsPolygon(id: tile.id, vertices: engine.polygon(for: tile.coordinate), color: color)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AtlasStatsMapLayer.allCases) { mode in
                        Button { layer = mode } label: {
                            Label(mode.label, systemImage: mode.iconName)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(layer == mode ? AtlasTheme.blue.opacity(0.15) : Color.secondary.opacity(0.08)))
                                .foregroundStyle(layer == mode ? AtlasTheme.blue : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Map(viewport: $viewport) {
                PolygonAnnotationGroup(overlays) { overlay in
                    let ring = Ring(coordinates: overlay.vertices + [overlay.vertices[0]])
                    return PolygonAnnotation(polygon: Polygon(outerRing: ring))
                        .fillColor(StyleColor(overlay.color))
                        .fillOpacity(0.48)
                        .fillOutlineColor(StyleColor(overlay.color))
                }
            }
            .mapStyle(.standard)
            .allowsHitTesting(interactive)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
        }
        .onAppear { viewport = .styleDefault }
    }

}

private struct StatsPolygon: Identifiable {
    let id: String
    let vertices: [CLLocationCoordinate2D]
    let color: UIColor
}

struct AtlasExplorerMapScreen: View {
    let tiles: [WorldTile]
    @Binding var layer: AtlasStatsMapLayer
    var frontierChargedTileIDs: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            AtlasStatsMapView(
                tiles: tiles,
                layer: $layer,
                frontierChargedTileIDs: frontierChargedTileIDs,
                interactive: true,
                height: UIScreen.main.bounds.height - 160
            )
            .padding(16)
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Atlas Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
