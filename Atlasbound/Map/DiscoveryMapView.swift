import SwiftUI
import MapKit

/// Renders discovered hex tiles, optional fog wash, and the live route on MapKit.
struct DiscoveryMapView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var recorder: ActivityRecorder

    @Binding var position: MapCameraPosition
    @Binding var followsUser: Bool

    /// When true (layers toggle), show mastery markers on top of fills.
    var showLayers: Bool = false

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var cachedDiscovered: [WorldTile] = []
    @State private var cachedFog: [TileCoordinate] = []
    @State private var cachedMarkers: [WorldTile] = []

    private var engine: TileEngine { store.tileEngine }

    var body: some View {
        Map(position: $position) {
            if recorder.isSimulationActive, let coordinate = recorder.lastLocation?.coordinate {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    SimulatedUserDot()
                }
            } else {
                UserAnnotation()
            }

            // Fill-only fog (no stroke) — cheaper for MapKit.
            ForEach(cachedFog, id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(AtlasTheme.fogWashFill)
                }
            }

            ForEach(cachedDiscovered) { tile in
                let vertices = engine.polygon(for: tile.coordinate)
                if vertices.count >= 3 {
                    let fresh = controller.sessionDiscoveredIDs.contains(tile.id)
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(tile.state.mapFill(isFreshDiscovery: fresh))
                        .stroke(
                            tile.state.mapStroke(isFreshDiscovery: fresh),
                            lineWidth: tile.state.mapStrokeWidth(isFreshDiscovery: fresh)
                        )
                }
            }

            ForEach(cachedMarkers) { tile in
                if let symbol = tile.state.markerSymbol {
                    Annotation("", coordinate: engine.centerCoordinate(for: tile.coordinate), anchor: .center) {
                        TileMarkerView(symbol: symbol, tint: tile.state.markerTint)
                    }
                }
            }

            if controller.liveRoute.count >= 2 {
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(AtlasTheme.routeOutline, lineWidth: AtlasTheme.routeOutlineWidth)
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(AtlasTheme.blue, lineWidth: AtlasTheme.routeLineWidth)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            refreshOverlays()
        }
        .onAppear {
            controller.prepareLocation()
            refreshOverlays()
        }
        .onChange(of: store.discoveredTiles.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.sessionDiscoveredIDs.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showLayers) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.isRecording) { _, _ in
            refreshOverlays()
        }
        .onChange(of: recorder.lastLocation?.coordinate.latitude) { _, _ in
            refreshOverlays()
            guard followsUser, let location = recorder.lastLocation else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: controller.isRecording ? 650 : 950,
                        longitudinalMeters: controller.isRecording ? 650 : 950
                    )
                )
            }
        }
    }

    private func refreshOverlays() {
        let engine = store.tileEngine
        let discovered = cullDiscovered(engine: engine)
        cachedDiscovered = discovered
        cachedFog = buildFog(engine: engine)
        cachedMarkers = showLayers
            ? Array(
                discovered
                    .filter { $0.state.markerSymbol != nil }
                    .sorted { $0.state.rawValue > $1.state.rawValue }
                    .prefix(AtlasTheme.maxVisibleMarkers)
              )
            : []
    }

    private func cullDiscovered(engine: TileEngine) -> [WorldTile] {
        MapOverlayCuller.cullTiles(
            store.discoveredTiles,
            engine: engine,
            visibleRegion: visibleRegion
        )
    }

    /// Local fog around the player — enough to read the grid without filling the whole camera.
    private func buildFog(engine: TileEngine) -> [TileCoordinate] {
        let anchor = recorder.lastLocation?.coordinate ?? visibleRegion?.center
        let radius = controller.isRecording ? AtlasTheme.fogRadiusRecording : AtlasTheme.fogRadiusIdle
        let tiles = controller.nearbyFogTiles(around: anchor, radius: radius)
        if tiles.count <= AtlasTheme.maxFogPolygons {
            return tiles
        }
        return Array(tiles.prefix(AtlasTheme.maxFogPolygons))
    }

}

struct TileMarkerView: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            HexShape()
                .fill(tint.opacity(0.92))
                .frame(width: 22, height: 24)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }
}

struct SimulatedUserDot: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AtlasTheme.blue.opacity(0.22))
                .frame(width: 36, height: 36)
            Circle()
                .fill(AtlasTheme.blue)
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
        }
        .allowsHitTesting(false)
    }
}

struct HexShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w, y: h * 0.25))
        path.addLine(to: CGPoint(x: w, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.5, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.75))
        path.addLine(to: CGPoint(x: 0, y: h * 0.25))
        path.closeSubpath()
        return path
    }
}
