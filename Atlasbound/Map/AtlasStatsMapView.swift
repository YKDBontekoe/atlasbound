import SwiftUI
import MapKit
import UIKit

enum AtlasStatsMapLayer: String, CaseIterable, Identifiable {
    case mastery
    case activity
    case discoveryAge
    case visitHeat
    case frontier

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mastery: "Mastery"
        case .activity: "Activity"
        case .discoveryAge: "Age"
        case .visitHeat: "Heat"
        case .frontier: "Frontier"
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

struct AtlasStatsTileOverlay: Identifiable {
    let id: String
    let coordinate: TileCoordinate
    let tileSizeMeters: Int
    let fill: Color
    let stroke: Color
    let strokeWidth: CGFloat
}

/// Read-only layered map for atlas statistics.
struct AtlasStatsMapView: View {
    let tiles: [WorldTile]
    @Binding var layer: AtlasStatsMapLayer
    var frontierChargedTileIDs: Set<String> = []
    var interactive: Bool = true
    var height: CGFloat = 220

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var cachedOverlays: [AtlasStatsTileOverlay] = []

    var body: some View {
        VStack(spacing: 10) {
            layerPicker

            Map(position: $position, interactionModes: interactive ? .all : []) {
                ForEach(cachedOverlays) { overlay in
                    let engine = TileEngine(tileSizeMeters: Double(overlay.tileSizeMeters))
                    let vertices = engine.polygon(for: overlay.coordinate)
                    if vertices.count >= 3 {
                        MapPolygon(coordinates: vertices)
                            .foregroundStyle(overlay.fill)
                            .stroke(overlay.stroke, lineWidth: overlay.strokeWidth)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                    .strokeBorder(AtlasTheme.chromeStroke(for: .light).opacity(0.5), lineWidth: 1)
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                refreshOverlays()
            }
            .onAppear {
                fitCamera()
                refreshOverlays()
            }
            .onChange(of: layer) { _, _ in
                refreshOverlays()
            }
        }
    }

    private var layerPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AtlasStatsMapLayer.allCases) { mode in
                    Button {
                        layer = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.iconName)
                                .font(.caption2.weight(.semibold))
                            Text(mode.label)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule()
                                .fill(layer == mode ? AtlasTheme.blue.opacity(0.15) : Color.secondary.opacity(0.08))
                        }
                        .foregroundStyle(layer == mode ? AtlasTheme.blue : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func fitCamera() {
        guard !tiles.isEmpty else { return }
        let centers = StatsEngine.tileCenters(tiles: tiles, tileSizeMeters: 20)
        guard let region = StatsEngine.boundingRegion(tileCenters: centers) else { return }
        position = .region(region)
        visibleRegion = region
    }

    private func refreshOverlays() {
        switch layer {
        case .mastery:
            cachedOverlays = buildMasteryOverlays()
        case .activity:
            cachedOverlays = buildActivityOverlays()
        case .discoveryAge:
            cachedOverlays = buildDiscoveryAgeOverlays()
        case .visitHeat:
            cachedOverlays = buildVisitHeatOverlays()
        case .frontier:
            cachedOverlays = buildFrontierOverlays()
        }
    }

    private func cullCurrentGrid() -> [WorldTile] {
        MapOverlayCuller.cullTiles(
            tiles.filter(\.isDiscovered),
            engine: TileEngine(option: .twenty),
            visibleRegion: visibleRegion
        )
    }

    private func buildMasteryOverlays() -> [AtlasStatsTileOverlay] {
        let visible = cullCurrentGrid()
        let engine = TileEngine(option: .twenty)
        let discoveredIDs = Set(tiles.filter(\.isDiscovered).map(\.id))
        let perimeterIDs = engine.territoryPerimeterIDs(among: visible, discoveredIDs: discoveredIDs)
        return visible.map { tile in
            let perimeter = perimeterIDs.contains(tile.id)
            return AtlasStatsTileOverlay(
                id: tile.id,
                coordinate: tile.coordinate,
                tileSizeMeters: 20,
                fill: tile.state.mapFill(isFreshDiscovery: false),
                stroke: tile.state.mapStroke(isFreshDiscovery: false, isPerimeter: perimeter),
                strokeWidth: tile.state.mapStrokeWidth(isFreshDiscovery: false, isPerimeter: perimeter)
            )
        }
    }

    private func buildActivityOverlays() -> [AtlasStatsTileOverlay] {
        cullCurrentGrid().map { tile in
            let activity = StatsEngine.dominantActivity(for: tile) ?? .unknown
            let color = activity.statsMapColor
            return AtlasStatsTileOverlay(
                id: tile.id,
                coordinate: tile.coordinate,
                tileSizeMeters: 20,
                fill: color.opacity(0.48),
                stroke: color.opacity(0.9),
                strokeWidth: 1
            )
        }
    }

    private func buildDiscoveryAgeOverlays() -> [AtlasStatsTileOverlay] {
        let visible = cullCurrentGrid()
        let dates = visible.compactMap(\.firstVisitedAt)
        let minDate = dates.min() ?? .now
        let maxDate = dates.max() ?? .now
        let span = max(maxDate.timeIntervalSince(minDate), 1)

        return visible.map { tile in
            let age = tile.firstVisitedAt.map { maxDate.timeIntervalSince($0) } ?? span
            let normalized = 1 - min(1, age / span)
            let fill = Color(
                red: 0.55 + normalized * 0.4,
                green: 0.62 + normalized * 0.13,
                blue: 0.70 - normalized * 0.5
            )
            let goldMix = normalized
            let blended = Color(
                red: fill.components.red * (1 - goldMix) + 0.95 * goldMix,
                green: fill.components.green * (1 - goldMix) + 0.75 * goldMix,
                blue: fill.components.blue * (1 - goldMix) + 0.2 * goldMix
            )
            return AtlasStatsTileOverlay(
                id: tile.id,
                coordinate: tile.coordinate,
                tileSizeMeters: 20,
                fill: blended.opacity(0.42 + normalized * 0.3),
                stroke: blended.opacity(0.75 + normalized * 0.2),
                strokeWidth: 0.8 + normalized
            )
        }
    }

    private func buildVisitHeatOverlays() -> [AtlasStatsTileOverlay] {
        let visible = cullCurrentGrid()
        let maxVisits = max(visible.map(\.visitCount).max() ?? 1, 1)

        return visible.map { tile in
            let intensity = min(1, Double(tile.visitCount) / Double(maxVisits))
            return AtlasStatsTileOverlay(
                id: tile.id,
                coordinate: tile.coordinate,
                tileSizeMeters: 20,
                fill: AtlasTheme.teal.opacity(0.15 + intensity * 0.55),
                stroke: AtlasTheme.gold.opacity(0.3 + intensity * 0.7),
                strokeWidth: 0.8 + CGFloat(intensity) * 1.5
            )
        }
    }

    private func buildFrontierOverlays() -> [AtlasStatsTileOverlay] {
        cullCurrentGrid().map { tile in
            let charge = tile.weeklyCharge
            let isCharged = frontierChargedTileIDs.contains(tile.id) || charge > 0
            let intensity = isCharged ? min(1, 0.25 + Double(max(charge, 1)) * 0.22) : 0.12
            return AtlasStatsTileOverlay(
                id: tile.id,
                coordinate: tile.coordinate,
                tileSizeMeters: 20,
                fill: AtlasTheme.gold.opacity(intensity),
                stroke: isCharged ? AtlasTheme.gold.opacity(0.9) : AtlasTheme.slate.opacity(0.35),
                strokeWidth: isCharged ? 1.2 + CGFloat(charge) * 0.3 : 0.6
            )
        }
    }

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

private extension Color {
    var components: (red: Double, green: Double, blue: Double) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
        #else
        return (0.5, 0.5, 0.5)
        #endif
    }
}
