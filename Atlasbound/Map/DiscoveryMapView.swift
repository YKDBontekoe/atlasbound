import SwiftUI
import MapKit

/// Renders discovered hex tiles, optional fog wash, and the live route on MapKit.
struct DiscoveryMapView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var recorder: ActivityRecorder

    @Binding var position: MapCameraPosition
    @Binding var followsUser: Bool

    var mapStyle: LiveMapStyle = .explorer
    var dataLayer: LiveMapDataLayer = .mastery
    var is3DEnabled: Bool = false
    var showsMasteryLayer: Bool = true
    var showsPlacesLayer: Bool = true
    var showsFogLayer: Bool = true
    var showsFrontierLayer: Bool = true
    var showsFactoryLayer: Bool = true
    @ObservedObject var factoryController: FactoryController
    @Binding var factoryPreviewTileID: String?
    var onTreasureTap: () -> Void = {}

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var cachedDiscovered: [WorldTile] = []
    @State private var cachedFog: [TileCoordinate] = []
    @State private var cachedMarkers: [WorldTile] = []
    @State private var cachedFrontierEdge: [TileCoordinate] = []
    @State private var cachedTargetBoundary: [TileCoordinate] = []
    @State private var cachedPlacePins: [PlaceMapPin] = []
    @State private var cachedPerimeterIDs: Set<String> = []
    @State private var cachedMaximumVisitCount = 1
    @State private var lastCamera: MapCamera?

    private var engine: TileEngine { store.tileEngine }

    var body: some View {
        MapReader { proxy in
            Map(
                position: $position,
                interactionModes: is3DEnabled ? .all : [.pan, .zoom, .rotate]
            ) {
            if recorder.isSimulationActive, let coordinate = recorder.lastLocation?.coordinate {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    SimulatedUserDot()
                }
            } else {
                UserAnnotation()
            }

            // Fill-only fog (no stroke) — cheaper for MapKit.
            ForEach(showsFogLayer ? cachedFog : [], id: \.self) { axial in
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
                        .foregroundStyle(discoveredFill(for: tile, isFresh: fresh, weeklyCharge: charge))
                        .stroke(
                            discoveredStroke(for: tile, isFresh: fresh, isPerimeter: perimeter),
                            lineWidth: discoveredStrokeWidth(for: tile, isFresh: fresh, isPerimeter: perimeter)
                        )
                }
            }

            // Soft gold wash on undiscovered frontier neighbors — fill only to avoid double edges.
            ForEach(showsFrontierLayer ? cachedFrontierEdge : [], id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(AtlasTheme.frontierWashFill)
                }
            }

            ForEach(showsFrontierLayer ? cachedTargetBoundary : [], id: \.self) { axial in
                let vertices = engine.polygon(for: axial)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(Color.clear)
                        .stroke(AtlasTheme.targetBoundaryStroke, lineWidth: AtlasTheme.targetBoundaryStrokeWidth)
                }
            }

            if showsFrontierLayer, let beacon = controller.expeditionBeaconCoordinate {
                Annotation("", coordinate: beacon, anchor: .center) {
                    ExpeditionBeaconView()
                }
            }

            if let treasure = controller.treasureTargetCoordinate {
                Annotation("Treasure", coordinate: treasure, anchor: .center) {
                    Button(action: onTreasureTap) {
                        TreasureMapMarkerView(isVault: controller.treasureStore.weeklyVault.isUnlocked)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(controller.fieldFindPreviews) { preview in
                if let coordinate = engine.parseTileID(preview.tileID).map({ engine.centerCoordinate(for: $0) }) {
                    Annotation("Field find", coordinate: coordinate, anchor: .center) {
                        FieldFindMapMarkerView(rarity: preview.rarity)
                    }
                }
            }

            ForEach(controller.frontierScoreCallouts) { callout in
                if let coordinate = engine.parseTileID(callout.tileID).map({ engine.centerCoordinate(for: $0) }) {
                    Annotation("", coordinate: coordinate, anchor: .bottom) {
                        FrontierScoreCalloutView(points: callout.points)
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

            ForEach(factoryController.isBuildModeActive ? factoryDepositPreviews : []) { preview in
                if let axial = engine.parseTileID(preview.tileID) {
                    Annotation(
                        preview.deposit.kind.displayName,
                        coordinate: engine.centerCoordinate(for: axial),
                        anchor: .center
                    ) {
                        FactoryDepositMarkerView(deposit: preview.deposit)
                    }
                }
            }

            ForEach(showsFactoryLayer ? factoryRoadLinks : []) { link in
                MapPolyline(coordinates: [link.start, link.end])
                    .stroke(AtlasTheme.gold.opacity(0.62), lineWidth: 4)
            }

            ForEach(showsFactoryLayer ? visibleFactoryStructures.filter { structure in
                FactoryCatalog.byID[structure.definitionID]?.kind == .road
            } : []) { structure in
                if let axial = engine.parseTileID(structure.tileID) {
                    MapPolygon(coordinates: engine.polygon(for: axial))
                        .foregroundStyle(AtlasTheme.gold.opacity(0.22))
                        .stroke(AtlasTheme.gold.opacity(0.8), lineWidth: 1)
                }
            }

            ForEach(showsFactoryLayer ? visibleFactoryStructures.filter { structure in
                FactoryCatalog.byID[structure.definitionID]?.kind != .road
            } : []) { structure in
                if let axial = engine.parseTileID(structure.tileID),
                   let definition = FactoryCatalog.byID[structure.definitionID] {
                    Annotation(definition.name, coordinate: engine.centerCoordinate(for: axial), anchor: .center) {
                        Button {
                            factoryController.selectedStructureID = structure.tileID
                        } label: {
                            FactoryMapMarkerView(
                                definition: definition,
                                status: factoryController.status(for: structure)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if factoryController.isBuildModeActive,
               let previewID = factoryPreviewTileID,
               let axial = engine.parseTileID(previewID) {
                let validation = factoryController.validation(for: previewID)
                MapPolygon(coordinates: engine.polygon(for: axial))
                    .foregroundStyle((validation.isAllowed ? AtlasTheme.teal : AtlasTheme.finishRed).opacity(0.28))
                    .stroke(validation.isAllowed ? AtlasTheme.teal : AtlasTheme.finishRed, lineWidth: 2.5)
            }

            if controller.liveRoute.count >= 2 {
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(AtlasTheme.routeOutline, lineWidth: AtlasTheme.routeOutlineWidth)
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(AtlasTheme.blue, lineWidth: AtlasTheme.routeLineWidth)
            }
            }
            .modifier(LiveMapStyleModifier(style: mapStyle))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            lastCamera = context.camera
            refreshOverlays()
        }
        .onAppear {
            controller.prepareLocation()
            refreshOverlays()
        }
        .onReceive(store.$tiles) { _ in
            refreshOverlays()
        }
        .onReceive(factoryController.store.$state) { _ in
            refreshOverlays()
        }
        .onChange(of: controller.sessionDiscoveredIDs.count) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.frontierEdgeTileIDs) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.targetSectorBoundaryTileIDs) { _, _ in
            refreshOverlays()
        }
        .onChange(of: controller.regionLookup.resolvedCellCount) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showsMasteryLayer) { _, _ in
            refreshOverlays()
        }
        .onChange(of: dataLayer) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showsPlacesLayer) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showsFogLayer) { _, _ in
            refreshOverlays()
        }
        .onChange(of: showsFrontierLayer) { _, _ in
            refreshOverlays()
        }
        .onChange(of: is3DEnabled) { _, _ in
            applyCameraPitch()
        }
        .onChange(of: controller.isRecording) { _, _ in
            refreshOverlays()
        }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in
            controller.prepareTreasureTrail()
            refreshOverlays()
            guard followsUser, let location = recorder.lastLocation else { return }
            let span = controller.isRecording
                ? AtlasTheme.mapSpanRecordingMeters
                : AtlasTheme.mapSpanIdleMeters
            withAnimation(AtlasMotion.camera) {
                if is3DEnabled {
                    position = .camera(
                        MapCamera(
                            centerCoordinate: location.coordinate,
                            distance: span,
                            heading: lastCamera?.heading ?? 0,
                            pitch: 58
                        )
                    )
                } else {
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
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard let coordinate = proxy.convert(value.location, from: .local) else { return }
                let tileID = engine.tileID(for: coordinate)
                if factoryController.isBuildModeActive {
                    factoryPreviewTileID = tileID
                } else if factoryController.store.structures[tileID] != nil {
                    factoryController.selectedStructureID = tileID
                }
            }
        )
        }
    }

    private func refreshOverlays() {
        let engine = store.tileEngine
        let discovered = cullDiscovered(engine: engine)
        let discoveredIDs = store.discoveredTileIDs
        cachedDiscovered = discovered
        cachedMaximumVisitCount = max(discovered.map(\.visitCount).max() ?? 1, 1)
        cachedPerimeterIDs = engine.territoryPerimeterIDs(among: discovered, discoveredIDs: discoveredIDs)
        cachedFog = buildFog(engine: engine)
        cachedFrontierEdge = controller.frontierEdgeTileIDs.compactMap { engine.parseTileID($0) }
        cachedTargetBoundary = controller.targetSectorBoundaryTileIDs.compactMap { engine.parseTileID($0) }
        cachedPlacePins = showsPlacesLayer
            ? Array(controller.placeMapPins.prefix(AtlasTheme.maxVisiblePlacePins))
            : []
        cachedMarkers = showsMasteryLayer
            ? Array(
                discovered
                    .filter { $0.state.markerSymbol != nil }
                    .sorted { $0.state.rawValue > $1.state.rawValue }
                    .prefix(AtlasTheme.maxVisibleMarkers)
              )
            : []
    }

    private func applyCameraPitch() {
        let center = lastCamera?.centerCoordinate
            ?? recorder.lastLocation?.coordinate
            ?? visibleRegion?.center
        guard let center else { return }
        let distance = lastCamera?.distance
            ?? (controller.isRecording ? AtlasTheme.mapSpanRecordingMeters : AtlasTheme.mapSpanIdleMeters)
        let heading = lastCamera?.heading ?? 0
        withAnimation(AtlasMotion.camera) {
            position = .camera(
                MapCamera(
                    centerCoordinate: center,
                    distance: distance,
                    heading: heading,
                    pitch: is3DEnabled ? 58 : 0
                )
            )
        }
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

    private func discoveredFill(for tile: WorldTile, isFresh: Bool, weeklyCharge: Int) -> Color {
        guard dataLayer == .visitHeat else {
            return tile.state.mapFill(isFreshDiscovery: isFresh, weeklyCharge: weeklyCharge)
        }
        let intensity = min(1, Double(tile.visitCount) / Double(cachedMaximumVisitCount))
        return AtlasTheme.teal.opacity((isFresh ? 0.42 : 0.12) + intensity * 0.52)
    }

    private func discoveredStroke(for tile: WorldTile, isFresh: Bool, isPerimeter: Bool) -> Color {
        guard dataLayer == .visitHeat else {
            return tile.state.mapStroke(isFreshDiscovery: isFresh, isPerimeter: isPerimeter)
        }
        guard isPerimeter else { return .clear }
        let intensity = min(1, Double(tile.visitCount) / Double(cachedMaximumVisitCount))
        return AtlasTheme.gold.opacity(0.35 + intensity * 0.65)
    }

    private func discoveredStrokeWidth(for tile: WorldTile, isFresh: Bool, isPerimeter: Bool) -> CGFloat {
        guard dataLayer == .visitHeat else {
            return tile.state.mapStrokeWidth(isFreshDiscovery: isFresh, isPerimeter: isPerimeter)
        }
        return isPerimeter ? 1.5 : 0
    }

    private var visibleFactoryStructures: [PlacedFactoryStructure] {
        let all = factoryController.structures
        guard let region = visibleRegion else { return Array(all.prefix(500)) }
        let minLat = region.center.latitude - region.span.latitudeDelta * 0.65
        let maxLat = region.center.latitude + region.span.latitudeDelta * 0.65
        let minLon = region.center.longitude - region.span.longitudeDelta * 0.65
        let maxLon = region.center.longitude + region.span.longitudeDelta * 0.65
        return Array(all.filter { structure in
            guard let axial = engine.parseTileID(structure.tileID) else { return false }
            let coordinate = engine.centerCoordinate(for: axial)
            return coordinate.latitude >= minLat && coordinate.latitude <= maxLat
                && coordinate.longitude >= minLon && coordinate.longitude <= maxLon
        }.prefix(500))
    }

    private var factoryRoadLinks: [FactoryRoadLink] {
        let roads = Dictionary(uniqueKeysWithValues: visibleFactoryStructures.compactMap { structure -> (String, PlacedFactoryStructure)? in
            FactoryCatalog.byID[structure.definitionID]?.kind == .road ? (structure.tileID, structure) : nil
        })
        return roads.keys.sorted().flatMap { tileID -> [FactoryRoadLink] in
            guard let axial = engine.parseTileID(tileID) else { return [] }
            return engine.neighbors(of: axial).compactMap { neighbor in
                let neighborID = TileEngine.makeTileID(q: neighbor.q, r: neighbor.r, sizeMeters: engine.tileSizeMeters)
                guard neighborID > tileID, roads[neighborID] != nil else { return nil }
                return FactoryRoadLink(
                    id: "\(tileID)|\(neighborID)",
                    start: engine.centerCoordinate(for: axial),
                    end: engine.centerCoordinate(for: neighbor)
                )
            }
        }
    }

    private var factoryDepositPreviews: [FactoryDepositPreview] {
        Array(
            cachedDiscovered.lazy
                .filter { $0.state.rawValue >= TileState.explored.rawValue }
                .filter { factoryController.store.structures[$0.id] == nil }
                .compactMap { tile in
                    let deposit = ConstructionEngine().deposit(for: tile.id)
                    guard deposit.kind != .empty else { return nil }
                    return FactoryDepositPreview(tileID: tile.id, deposit: deposit)
                }
                .prefix(80)
        )
    }

}

private struct FactoryRoadLink: Identifiable {
    let id: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
}

private struct FactoryDepositPreview: Identifiable {
    var id: String { tileID }
    let tileID: String
    let deposit: FactoryDeposit
}

struct FactoryDepositMarkerView: View {
    let deposit: FactoryDeposit

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(AtlasTheme.gold.opacity(0.88), in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityLabel("\(deposit.kind.displayName), \(deposit.capacity) units")
            .accessibilityHint("A Gathering Outpost can extract this revealed deposit.")
    }

    private var symbolName: String {
        switch deposit.kind {
        case .cobble: "hexagon.fill"
        case .moss: "leaf.fill"
        case .copper: "circle.hexagongrid.fill"
        case .amber: "drop.fill"
        case .waystone: "diamond.fill"
        case .empty: "minus"
        }
    }
}

struct FactoryMapMarkerView: View {
    let definition: FactoryStructureDefinition
    let status: FactoryOperationalStatus

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: definition.symbolName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(AtlasTheme.slate.gradient, in: HexShape())
                .overlay {
                    HexShape().stroke(AtlasTheme.gold.opacity(0.9), lineWidth: 1.5)
                }
                .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
            if status != .running {
                Circle()
                    .fill(status == .idle ? AtlasTheme.gold : AtlasTheme.finishRed)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.white, lineWidth: 1))
                    .offset(x: 2, y: -2)
            }
        }
        .accessibilityLabel("\(definition.name), \(status.displayName)")
        .accessibilityHint("Tap to open structure details.")
    }
}

private struct LiveMapStyleModifier: ViewModifier {
    let style: LiveMapStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .explorer:
            content.mapStyle(
                .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
            )
        case .satellite:
            content.mapStyle(.imagery(elevation: .realistic))
        case .hybrid:
            content.mapStyle(
                .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
            )
        }
    }
}

struct TreasureMapMarkerView: View {
    let isVault: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(AtlasTheme.gold.opacity(0.45), lineWidth: 3)
                .frame(width: pulse ? 48 : 34, height: pulse ? 48 : 34)
                .opacity(pulse ? 0.15 : 0.7)
            Image(systemName: isVault ? "lock.open.fill" : "map.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .padding(10)
                .background(AtlasTheme.gold, in: Circle())
                .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(AtlasMotion.ambient.repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(isVault ? "Weekly vault" : "Treasure clue")
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
