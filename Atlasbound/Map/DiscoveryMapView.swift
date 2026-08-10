import SwiftUI
import CoreLocation
import UIKit
import MapboxMaps

/// Mapbox renderer for the live atlas. Domain geometry is still derived by TileEngine.
struct DiscoveryMapView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var recorder: ActivityRecorder

    @Binding var position: Viewport
    @Binding var followsUser: Bool
    @Binding var selectedTileID: String?

    var dataLayer: LiveMapDataLayer = .mastery
    var showsMasteryLayer: Bool = true
    var showsPlacesLayer: Bool = true
    var showsFrontierLayer: Bool = true
    var showsFactoryLayer: Bool = true
    @ObservedObject var factoryController: FactoryController
    @Binding var factoryPreviewTileID: String?
    var onLandmarkQuestTap: () -> Void = {}

    private var engine: TileEngine { store.tileEngine }
    private var sectorEngine: HexSectorEngine { HexSectorEngine() }

    private var claimedSectorIDs: [String] {
        store.territoryState.claims.map(\.sectorID).sorted()
    }

    private var homeSectorID: String? {
        store.territoryState.homeSectorID
    }

    @State private var overlays: [MapboxPolygonOverlay] = []
    @State private var mapZoom = 15.0
    @Environment(\.colorScheme) private var colorScheme

    private var lod: MapTileLOD {
        if mapZoom >= 15 { return .near }
        if mapZoom >= 12 { return .mid }
        return .far
    }

    private var frontierSignalTiles: [TileCoordinate] {
        guard showsFrontierLayer, lod != .far else { return [] }
        let player = recorder.lastLocation.map { engine.axialCoordinate(for: $0.coordinate) }
        return controller.frontierEdgeTileIDs
            .compactMap(engine.parseTileID)
            .sorted { lhs, rhs in
                guard let player else { return lhs < rhs }
                let lhsDistance = TileEngine.hexDistance(lhs, player)
                let rhsDistance = TileEngine.hexDistance(rhs, player)
                return lhsDistance == rhsDistance ? lhs < rhs : lhsDistance < rhsDistance
            }
            .prefix(lod == .near ? 8 : 4)
            .map { $0 }
    }

    /// A convex hull around the generated sector members gives Mapbox one
    /// inexpensive, continuous territory shape instead of hundreds of faint
    /// boundary hex annotations. The vertices are derived at render time from
    /// the persisted sector ID, so no geometry is stored.
    private func claimedSectorOverlay(for sectorID: String) -> MapboxPolygonOverlay? {
        guard let parsed = sectorEngine.parseSectorID(sectorID),
              parsed.sizeMeters == Int(engine.tileSizeMeters.rounded()) else {
            return nil
        }
        let coordinates = sectorEngine.tiles(in: parsed.sector)
            .flatMap { engine.polygon(for: $0) }
        let hull = convexHull(of: coordinates)
        guard hull.count >= 3 else { return nil }
        return MapboxPolygonOverlay(
            id: "sector:\(sectorID)",
            vertices: hull,
            fill: .claimedSector(isHome: sectorID == homeSectorID)
        )
    }

    private func convexHull(of coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var sorted = coordinates.map { point in
            CGPoint(x: point.longitude, y: point.latitude)
        }
        sorted.sort { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
        guard sorted.count > 2 else {
            return sorted.map { CLLocationCoordinate2D(latitude: $0.y, longitude: $0.x) }
        }

        func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        var lower: [CGPoint] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        let hull = lower.dropLast() + upper.dropLast()
        return hull.map { CLLocationCoordinate2D(latitude: $0.y, longitude: $0.x) }
    }

    private func makeOverlays() -> [MapboxPolygonOverlay] {
        var result: [MapboxPolygonOverlay] = []
        result += claimedSectorIDs.compactMap { claimedSectorOverlay(for: $0) }
        let discovered = Array(store.discoveredTiles.prefix(lod.polygonCap))
        let discoveredIDs = Set(discovered.map(\.id))
        let claimedIDs = Set(claimedSectorIDs)
        let maximumVisitCount = max(discovered.map(\.visitCount).max() ?? 1, 1)
        result += discovered.map { tile in
            let sectorID = sectorEngine.sectorID(for: tile.coordinate, sizeMeters: engine.tileSizeMeters)
            let isClaimed = claimedIDs.contains(sectorID)
            let isPerimeter = engine.neighbors(of: tile.coordinate).contains {
                !discoveredIDs.contains(TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: engine.tileSizeMeters))
            }
            return polygonOverlay(
                id: "tile:\(tile.id)",
                coordinate: tile.coordinate,
                fill: .tile(
                    tile,
                    dataLayer: dataLayer,
                    maximumVisitCount: maximumVisitCount,
                    isPerimeter: isPerimeter,
                    isFresh: controller.sessionDiscoveredIDs.contains(tile.id),
                    isClaimed: isClaimed,
                    isHomeBase: isClaimed && sectorID == homeSectorID,
                    lod: lod
                )
            )
        }
        if showsFrontierLayer {
            result += controller.frontierEdgeTileIDs.prefix(lod.polygonCap).compactMap { id in
                guard let coordinate = engine.parseTileID(id) else { return nil }
                return polygonOverlay(id: id, coordinate: coordinate, fill: .frontier)
            }
        }
        if showsFrontierLayer {
            result += controller.targetSectorBoundaryTileIDs.prefix(lod.polygonCap).compactMap { id in
                guard let coordinate = engine.parseTileID(id) else { return nil }
                return polygonOverlay(id: "target:\(id)", coordinate: coordinate, fill: .target)
            }
        }
        return result
    }

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width > 1, proxy.size.height > 1 {
                mapView
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 1, minHeight: 1)
    }

    private var mapView: some View {
        Map(viewport: $position) {
            Puck2D(bearing: .heading)
                .showsAccuracyRing(true)

            if let location = recorder.lastLocation {
                MapViewAnnotation(coordinate: location.coordinate) {
                    ExplorationPulseView(isActive: !controller.sessionDiscoveredIDs.isEmpty)
                }
            }

            ForEvery(controller.discoveryMoments) { moment in
                if let axial = engine.parseTileID(moment.tileID) {
                    MapViewAnnotation(coordinate: engine.centerCoordinate(for: axial)) {
                        DiscoveryRevealView()
                    }
                }
            }

            ForEvery(frontierSignalTiles, id: \.self) { tile in
                MapViewAnnotation(coordinate: engine.centerCoordinate(for: tile)) {
                    FrontierSignalView()
                }
            }

            if showsFrontierLayer, let beacon = controller.expeditionBeaconCoordinate {
                MapViewAnnotation(coordinate: beacon) {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.orange))
                }
            }

            if let home = controller.homeBaseCoordinate {
                MapViewAnnotation(coordinate: home) {
                    Image(systemName: "house.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(Color.blue))
                }
            }

            ForEvery(claimedSectorIDs, id: \.self) { sectorID in
                if let parsed = sectorEngine.parseSectorID(sectorID) {
                    MapViewAnnotation(coordinate: engine.centerCoordinate(for: sectorEngine.centerTile(for: parsed.sector))) {
                        TerritoryMapBadge(isHome: sectorID == homeSectorID)
                    }
                }
            }

            PolygonAnnotationGroup(overlays.filter { $0.vertices.count >= 3 }) { overlay in
                let ring = Ring(coordinates: overlay.vertices + [overlay.vertices[0]])
                return PolygonAnnotation(polygon: Polygon(outerRing: ring))
                    .fillColor(overlay.fill.color)
                    .fillOpacity(overlay.fill.opacity)
                    .fillOutlineColor(overlay.fill.outline)
            }

            if controller.liveRoute.count > 1 {
                PolylineAnnotation(lineCoordinates: controller.liveRoute)
                    .lineColor(StyleColor(.white))
                    .lineWidth(8)
                    .lineOpacity(0.55)
                PolylineAnnotation(lineCoordinates: controller.liveRoute)
                    .lineColor(StyleColor(UIColor(AtlasTheme.teal)))
                    .lineWidth(4.5)
                    .lineOpacity(0.85)
            }

            if let quest = controller.landmarkQuest,
               let axial = engine.parseTileID(quest.target.tileID) {
                MapViewAnnotation(coordinate: engine.centerCoordinate(for: axial)) {
                    Button(action: onLandmarkQuestTap) {
                        LandmarkQuestMapMarker(
                            quest: quest,
                            isVault: controller.treasureStore.weeklyVault.isUnlocked
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Focus landmark quest: \(quest.title)")
                }
            }

            if showsPlacesLayer {
                ForEvery(controller.placeMapPins) { pin in
                    MapViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)) {
                        Text(pin.name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                    }
                }
            }

            ForEvery(controller.fieldFindPreviews) { preview in
                if let axial = engine.parseTileID(preview.tileID) {
                    MapViewAnnotation(coordinate: engine.centerCoordinate(for: axial)) {
                        FieldFindMapMarkerView(rarity: preview.rarity)
                    }
                }
            }

            ForEvery(controller.frontierScoreCallouts) { callout in
                if let axial = engine.parseTileID(callout.tileID) {
                    MapViewAnnotation(coordinate: engine.centerCoordinate(for: axial)) {
                        Text("+\(callout.points)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Color.orange, in: Capsule())
                    }
                }
            }

            if showsMasteryLayer {
                ForEvery(store.discoveredTiles
                    .filter { tile in
                        guard let minimum = lod.minimumMarkerState else { return false }
                        return tile.state.rawValue >= minimum.rawValue && tile.state.markerSymbol != nil
                    }
                    .prefix(lod.markerCap)) { tile in
                    MapViewAnnotation(coordinate: engine.centerCoordinate(for: tile.coordinate)) {
                        Image(systemName: tile.state.markerSymbol ?? "hexagon.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(Color.indigo))
                    }
                }
            }

            CircleAnnotationGroup(controller.treasureStore.sharedEvents) { event in
                CircleAnnotation(centerCoordinate: event.coordinate)
                    .circleColor(StyleColor(.systemOrange))
                    .circleRadius(7)
                    .circleStrokeColor(StyleColor(.white))
                    .circleStrokeWidth(2)
            }

            if showsFactoryLayer {
                ForEvery(factoryController.structures.prefix(100)) { structure in
                    if let axial = engine.parseTileID(structure.tileID),
                       let definition = FactoryCatalog.byID[structure.definitionID],
                       definition.kind != .road {
                        MapViewAnnotation(coordinate: engine.centerCoordinate(for: axial)) {
                            Button {
                                factoryController.selectedStructureID = structure.tileID
                            } label: {
                                Image(systemName: definition.symbolName)
                                    .foregroundStyle(.white)
                                    .padding(7)
                                    .background(Circle().fill(Color.brown))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            TapInteraction { context in
                let tileID = engine.tileID(for: context.coordinate)
                if factoryController.isBuildModeActive {
                    factoryPreviewTileID = tileID
                } else {
                    selectedTileID = tileID
                }
                AtlasHaptics.select()
                return false
            }
        }
        .mapStyle(AtlasMapStyle.standard(for: colorScheme))
        .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden)))
        .onCameraChanged { context in
            let zoom = context.cameraState.zoom
            if abs(zoom - mapZoom) > 0.15 {
                mapZoom = zoom
            }
            if followsUser {
                followsUser = false
            }
        }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in
            guard followsUser else { return }
            position = .followPuck(zoom: controller.isRecording ? 16 : 15, pitch: 42)
        }
        .onAppear {
            overlays = makeOverlays()
            position = .followPuck(zoom: 15, pitch: 42)
        }
        .onChange(of: store.discoveredTiles) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.frontierEdgeTileIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: store.territoryState) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.targetSectorBoundaryTileIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.isRecording) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.sessionDiscoveredIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: dataLayer) { _, _ in overlays = makeOverlays() }
        .onChange(of: mapZoom) { _, _ in overlays = makeOverlays() }
        .onChange(of: showsFrontierLayer) { _, _ in overlays = makeOverlays() }
        .frame(minWidth: 1, minHeight: 1)
    }

    private func polygonOverlay(id: String, coordinate: TileCoordinate, fill: MapboxPolygonFill) -> MapboxPolygonOverlay {
        MapboxPolygonOverlay(id: id, vertices: engine.polygon(for: coordinate), fill: fill)
    }
}

private struct MapboxPolygonOverlay: Identifiable {
    let id: String
    let vertices: [CLLocationCoordinate2D]
    let fill: MapboxPolygonFill
}

private struct MapboxPolygonFill {
    let color: StyleColor
    let outline: StyleColor
    let opacity: Double

    static let frontier = MapboxPolygonFill(
        color: StyleColor(UIColor(AtlasTheme.gold.opacity(0.12))),
        outline: StyleColor(UIColor(AtlasTheme.gold.opacity(0.82))),
        opacity: 1
    )
    static let target = MapboxPolygonFill(
        color: StyleColor(UIColor(AtlasTheme.blue.opacity(0.08))),
        outline: StyleColor(UIColor(AtlasTheme.targetBoundaryStroke)),
        opacity: 0.36
    )

    static func claimedSector(isHome: Bool) -> MapboxPolygonFill {
        let accent = isHome ? AtlasTheme.homeBaseAccent : AtlasTheme.claimedTerritoryStroke
        return MapboxPolygonFill(
            color: StyleColor(UIColor(accent.opacity(0.14))),
            outline: StyleColor(UIColor(accent.opacity(0.95))),
            opacity: 1
        )
    }

    static func tile(
        _ tile: WorldTile,
        dataLayer: LiveMapDataLayer,
        maximumVisitCount: Int,
        isPerimeter: Bool,
        isFresh: Bool,
        isClaimed: Bool = false,
        isHomeBase: Bool = false,
        lod: MapTileLOD
    ) -> MapboxPolygonFill {
        if dataLayer == .visitHeat {
            let intensity = min(1, Double(tile.visitCount) / Double(maximumVisitCount))
            let heat = AtlasTheme.blue.opacity(0.14 + intensity * 0.66)
            let rim = AtlasTheme.teal.opacity(0.42 + intensity * 0.48)
            return MapboxPolygonFill(
                color: StyleColor(UIColor(heat)),
                outline: StyleColor(UIColor(isPerimeter ? rim : .clear)),
                opacity: lod == .far ? 0.72 : 0.92
            )
        }

        if isClaimed {
            let accent = isHomeBase ? AtlasTheme.homeBaseAccent : AtlasTheme.teal
            return MapboxPolygonFill(
                color: StyleColor(UIColor(accent.opacity(lod == .far ? 0.18 : 0.30))),
                outline: StyleColor(UIColor(accent.opacity(0.95))),
                opacity: lod == .far ? 0.72 : 1
            )
        }

        let material = TileMapMaterial.resolve(
            state: tile.state,
            isFreshDiscovery: isFresh,
            weeklyCharge: tile.weeklyCharge,
            isPerimeter: isPerimeter,
            lod: lod
        )
        return MapboxPolygonFill(
            color: StyleColor(UIColor(material.fill)),
            outline: StyleColor(UIColor(material.outerStroke)),
            opacity: lod.drawsInteriorFills || isPerimeter ? 1 : 0
        )
    }
}

private struct ExplorationPulseView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(AtlasTheme.teal.opacity(0.24), lineWidth: 2)
                .frame(width: isActive ? 62 : 46, height: isActive ? 62 : 46)
                .animation(AtlasMotion.ambient, value: isActive)
            Circle()
                .fill(AtlasTheme.teal.opacity(0.18))
                .frame(width: 16, height: 16)
        }
        .allowsHitTesting(false)
    }
}

private struct DiscoveryRevealView: View {
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettledMotion

    var body: some View {
        let expanded = isExpanded || forceSettledMotion
        ZStack {
            Circle()
                .stroke(AtlasTheme.teal.opacity(expanded ? 0 : 0.85), lineWidth: 2)
                .frame(width: expanded ? 70 : 18, height: expanded ? 70 : 18)
            Circle()
                .fill(AtlasTheme.teal.opacity(expanded ? 0.08 : 0.56))
                .frame(width: expanded ? 44 : 14, height: expanded ? 44 : 14)
            Image(systemName: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(expanded ? 0.3 : 1))
        }
        .onAppear {
            AtlasMotion.withOptionalAnimation(.easeOut(duration: 1.45), reduceMotion: reduceMotion || forceSettledMotion) {
                isExpanded = true
            }
        }
        .allowsHitTesting(false)
    }
}

private struct FrontierSignalView: View {
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettledMotion

    var body: some View {
        let breathing = isBreathing || forceSettledMotion
        ZStack {
            Circle()
                .fill(AtlasTheme.gold.opacity(breathing ? 0.04 : 0.22))
                .frame(width: breathing ? 34 : 18, height: breathing ? 34 : 18)
            Circle()
                .stroke(AtlasTheme.gold.opacity(breathing ? 0.2 : 0.85), lineWidth: 1.4)
                .frame(width: breathing ? 28 : 12, height: breathing ? 28 : 12)
            Circle()
                .fill(AtlasTheme.gold)
                .frame(width: 5, height: 5)
        }
        .onAppear {
            AtlasMotion.withOptionalAnimation(
                AtlasMotion.ambient.repeatForever(autoreverses: true),
                reduceMotion: reduceMotion || forceSettledMotion
            ) {
                isBreathing = true
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LandmarkQuestMapMarker: View {
    let quest: LandmarkQuest
    let isVault: Bool
    @State private var isBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettledMotion

    var body: some View {
        let breathing = isBreathing || forceSettledMotion
        ZStack {
            Circle()
                .fill(AtlasTheme.blue.opacity(breathing ? 0.08 : 0.24))
                .frame(width: breathing ? 58 : 42, height: breathing ? 58 : 42)
            Image(systemName: isVault ? "lock.open.fill" : quest.symbolName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(isVault ? AtlasTheme.gold : AtlasTheme.blue))
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
        }
        .onAppear {
            AtlasMotion.withOptionalAnimation(
                AtlasMotion.ambient.repeatForever(autoreverses: true),
                reduceMotion: reduceMotion || forceSettledMotion
            ) {
                isBreathing = true
            }
        }
    }
}

private struct TerritoryMapBadge: View {
    let isHome: Bool

    var body: some View {
        Label(isHome ? "Home Base" : "Claimed", systemImage: isHome ? "house.fill" : "shield.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background((isHome ? AtlasTheme.homeBaseAccent : AtlasTheme.teal).gradient, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: .black.opacity(0.24), radius: 4, y: 2)
            .allowsHitTesting(false)
    }
}
