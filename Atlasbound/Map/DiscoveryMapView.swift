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
    @State private var cachedFrontierEdge: [TileCoordinate] = []
    @State private var cachedTargetBoundary: [TileCoordinate] = []
    @State private var cachedEventBoundary: [TileCoordinate] = []
    @State private var cachedEventHighlight: [TileCoordinate] = []
    @State private var cachedHotspots: [MapHotspot] = []
    @State private var cachedPlacePins: [PlaceMapPin] = []
    @State private var cachedPerimeterIDs: Set<String> = []

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
                    let charge = tile.weeklyCharge
                    let perimeter = cachedPerimeterIDs.contains(tile.id)
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(tile.state.mapFill(isFreshDiscovery: fresh, weeklyCharge: charge))
                        .stroke(
                            tile.state.mapStroke(isFreshDiscovery: fresh, isPerimeter: perimeter),
                            lineWidth: tile.state.mapStrokeWidth(isFreshDiscovery: fresh, isPerimeter: perimeter)
                        )
                }
            }

            // Soft gold wash on undiscovered frontier neighbors — fill only to avoid double edges.
            ForEach(cachedFrontierEdge, id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(AtlasTheme.frontierWashFill)
                }
            }

            // World-event sector wash (distinct from frontier gold).
            ForEach(cachedEventHighlight, id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(AtlasTheme.eventWashFill)
                }
            }

            ForEach(cachedTargetBoundary, id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(Color.clear)
                        .stroke(AtlasTheme.targetBoundaryStroke, lineWidth: AtlasTheme.targetBoundaryStrokeWidth)
                }
            }

            ForEach(cachedEventBoundary, id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(Color.clear)
                        .stroke(AtlasTheme.eventBoundaryStroke, lineWidth: AtlasTheme.eventBoundaryStrokeWidth)
                }
            }

            if let beacon = controller.expeditionBeaconCoordinate {
                Annotation("", coordinate: beacon, anchor: .center) {
                    ExpeditionBeaconView()
                }
            }

            if let eventBeacon = controller.eventBeaconCoordinate {
                Annotation("", coordinate: eventBeacon, anchor: .center) {
                    WorldEventBeaconView()
                }
            }

            ForEach(controller.frontierScoreCallouts) { callout in
                if let coordinate = engine.parseTileID(callout.tileID).map({ engine.centerCoordinate(for: $0) }) {
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        FrontierScoreCalloutView(points: callout.points)
                    }
                }
            }

            ForEach(cachedHotspots) { hotspot in
                if let axial = engine.parseTileID(hotspot.tileID) {
                    Annotation("", coordinate: engine.centerCoordinate(for: axial), anchor: .center) {
                        HotspotMarkerView(isVisited: hotspot.isVisited, isEventTarget: hotspot.isEventTarget)
                    }
                }
            }

            ForEach(cachedPlacePins) { pin in
                Annotation(pin.name, coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude), anchor: .bottom) {
                    PlaceVisitedPinView(name: pin.name)
                }
            }

            ForEach(cachedMarkers) { tile in
                if let symbol = tile.state.markerSymbol {
                    Annotation("", coordinate: engine.centerCoordinate(for: tile.coordinate), anchor: .center) {
                        TileMarkerView(symbol: symbol, tint: tile.state.markerTint)
                            .transition(.scale.combined(with: .opacity))
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
        .onChange(of: controller.frontierEdgeTileIDs.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.targetSectorBoundaryTileIDs.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.eventSectorBoundaryTileIDs.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.mapHotspots.map(\.id)) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.regionLookup.resolvedCellCount) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showLayers) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.isRecording) { _, _ in
            refreshOverlays()
        }
        .onChange(of: recorder.lastLocation?.coordinate.latitude) { _, _ in
            controller.refreshWorldEventPresentation()
            refreshOverlays()
            guard followsUser, let location = recorder.lastLocation else { return }
            let span = controller.isRecording
                ? AtlasTheme.mapSpanRecordingMeters
                : AtlasTheme.mapSpanIdleMeters
            withAnimation(AtlasMotion.camera) {
                position = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: span,
                        longitudinalMeters: span
                    )
                )
            }
        }
    }

    private func refreshOverlays() {
        let engine = store.tileEngine
        let discovered = cullDiscovered(engine: engine)
        let discoveredIDs = store.discoveredTileIDs
        cachedDiscovered = discovered
        cachedPerimeterIDs = engine.territoryPerimeterIDs(among: discovered, discoveredIDs: discoveredIDs)
        cachedFog = buildFog(engine: engine)
        cachedFrontierEdge = controller.frontierEdgeTileIDs.compactMap { engine.parseTileID($0) }
        cachedTargetBoundary = controller.targetSectorBoundaryTileIDs.compactMap { engine.parseTileID($0) }
        cachedEventBoundary = controller.eventSectorBoundaryTileIDs.compactMap { engine.parseTileID($0) }
        cachedEventHighlight = controller.eventHighlightTileIDs.compactMap { engine.parseTileID($0) }
        cachedHotspots = Array(controller.mapHotspots.prefix(AtlasTheme.maxVisibleHotspots))
        cachedPlacePins = showLayers
            ? Array(controller.placeMapPins.prefix(AtlasTheme.maxVisiblePlacePins))
            : []
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

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
        .scaleEffect(appeared || reduceMotion ? 1 : 0.5)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            AtlasMotion.withOptionalAnimation(AtlasMotion.celebrate, reduceMotion: reduceMotion) {
                appeared = true
            }
        }
        .allowsHitTesting(false)
    }
}

struct ExpeditionBeaconView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AtlasTheme.blue.opacity(0.35), lineWidth: 2)
                .frame(width: pulse ? 34 : 24, height: pulse ? 34 : 24)
                .opacity(pulse ? 0.2 : 0.6)
            Image(systemName: "flag.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(8)
                .background(AtlasTheme.blue, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AtlasMotion.ambient.repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .allowsHitTesting(false)
    }
}

struct WorldEventBeaconView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AtlasTheme.eventAccent.opacity(0.4), lineWidth: 2)
                .frame(width: pulse ? 38 : 26, height: pulse ? 38 : 26)
                .opacity(pulse ? 0.2 : 0.65)
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(8)
                .background(AtlasTheme.eventAccent, in: Circle())
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AtlasMotion.ambient.repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .allowsHitTesting(false)
    }
}

struct HotspotMarkerView: View {
    let isVisited: Bool
    let isEventTarget: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isVisited ? AtlasTheme.teal.opacity(0.85) : AtlasTheme.eventAccent.opacity(isEventTarget ? 0.95 : 0.75))
                .frame(width: 18, height: 18)
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            Image(systemName: isVisited ? "checkmark" : "circle.hexagongrid.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            AtlasMotion.withOptionalAnimation(AtlasMotion.celebrate, reduceMotion: reduceMotion) {
                appeared = true
            }
        }
        .allowsHitTesting(false)
    }
}

struct PlaceVisitedPinView: View {
    let name: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AtlasTheme.slate)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .lineLimit(1)
        }
        .allowsHitTesting(false)
    }
}

struct FrontierScoreCalloutView: View {
    let points: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        Text("+\(points)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(AtlasTheme.gold, in: Capsule())
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? -8 : -20)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(AtlasMotion.toastFade.delay(0.2)) {
                    visible = false
                }
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
