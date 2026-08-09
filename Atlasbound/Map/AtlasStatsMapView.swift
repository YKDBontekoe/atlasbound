import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

enum AtlasStatsMapLayer: String, CaseIterable, Identifiable {
    case mastery, activity, discoveryAge, visitHeat, frontier
    var id: String { rawValue }
    var label: String {
        switch self {
        case .discoveryAge: "Age"
        default: rawValue.capitalized
        }
    }
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
    @State private var overlays: [StatsPolygon] = []

    private func makeOverlays() -> [StatsPolygon] {
        let engine = TileEngine(tileSizeMeters: 20)
        let visible = Array(tiles.filter(\.isDiscovered).prefix(AtlasTheme.maxVisiblePolygons))
        let maximumVisitCount = max(visible.map(\.visitCount).max() ?? 1, 1)
        let dates = visible.compactMap(\.firstVisitedAt)
        let earliest = dates.min() ?? .now
        let latest = dates.max() ?? earliest
        let dateSpan = max(latest.timeIntervalSince(earliest), 1)

        return visible.map { tile in
            let color: UIColor
            let opacity: Double
            switch layer {
            case .mastery:
                color = UIColor(tile.state.mapBrandColor)
                opacity = 0.48
            case .activity:
                color = UIColor((StatsEngine.dominantActivity(for: tile) ?? .unknown).statsMapColor)
                opacity = 0.48
            case .discoveryAge:
                let age = tile.firstVisitedAt.map { latest.timeIntervalSince($0) } ?? dateSpan
                let intensity = 1 - min(1, age / dateSpan)
                color = UIColor(
                    red: 0.45 + intensity * 0.45,
                    green: 0.62 + intensity * 0.18,
                    blue: 0.78 - intensity * 0.48,
                    alpha: 1
                )
                opacity = 0.48
            case .visitHeat:
                let intensity = min(1, Double(tile.visitCount) / Double(maximumVisitCount))
                color = UIColor(red: 0.10, green: 0.62, blue: 0.62, alpha: 1)
                opacity = 0.15 + intensity * 0.75
            case .frontier:
                color = frontierChargedTileIDs.contains(tile.id) ? .systemYellow : .systemBlue
                opacity = 0.48
            }
            return StatsPolygon(id: tile.id, vertices: engine.polygon(for: tile.coordinate), color: color, opacity: opacity)
        }
    }

    private func updateMap() {
        overlays = makeOverlays()
        let engine = TileEngine(tileSizeMeters: 20)
        let centers = tiles.filter(\.isDiscovered).prefix(AtlasTheme.maxVisiblePolygons).map {
            engine.centerCoordinate(for: $0.coordinate)
        }
        guard let region = StatsEngine.boundingRegion(tileCenters: centers) else {
            viewport = .styleDefault
            return
        }
        let halfLat = region.latitudeDelta / 2
        let halfLon = region.longitudeDelta / 2
        let corners = [
            CLLocationCoordinate2D(latitude: region.center.latitude - halfLat, longitude: region.center.longitude - halfLon),
            CLLocationCoordinate2D(latitude: region.center.latitude + halfLat, longitude: region.center.longitude - halfLon),
            CLLocationCoordinate2D(latitude: region.center.latitude + halfLat, longitude: region.center.longitude + halfLon),
            CLLocationCoordinate2D(latitude: region.center.latitude - halfLat, longitude: region.center.longitude + halfLon),
            CLLocationCoordinate2D(latitude: region.center.latitude - halfLat, longitude: region.center.longitude - halfLon)
        ]
        viewport = .overview(geometry: Polygon(outerRing: Ring(coordinates: corners)))
    }

    private var statsMap: some View {
        Map(viewport: $viewport) {
            PolygonAnnotationGroup(overlays.filter { $0.vertices.count >= 3 }) { overlay in
                let ring = Ring(coordinates: overlay.vertices + [overlay.vertices[0]])
                return PolygonAnnotation(polygon: Polygon(outerRing: ring))
                    .fillColor(StyleColor(overlay.color))
                    .fillOpacity(overlay.opacity)
                    .fillOutlineColor(StyleColor(overlay.color))
            }
        }
        .mapStyle(.standard)
        .allowsHitTesting(interactive)
        .frame(minWidth: 1, minHeight: 1)
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

            GeometryReader { proxy in
                if proxy.size.width > 1, proxy.size.height > 1 {
                    statsMap
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Color.clear
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
        }
        .onAppear { updateMap() }
        .onChange(of: tiles) { _, _ in updateMap() }
        .onChange(of: layer) { _, _ in updateMap() }
        .onChange(of: frontierChargedTileIDs) { _, _ in updateMap() }
    }

}

private struct StatsPolygon: Identifiable {
    let id: String
    let vertices: [CLLocationCoordinate2D]
    let color: UIColor
    let opacity: Double
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
