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

    private var engine: TileEngine { store.tileEngine }

    @State private var overlays: [MapboxPolygonOverlay] = []

    private func makeOverlays() -> [MapboxPolygonOverlay] {
        var result: [MapboxPolygonOverlay] = []
        if showsFogLayer {
            let fogRadius = controller.isRecording ? AtlasTheme.fogRadiusRecording : AtlasTheme.fogRadiusIdle
            result += controller.nearbyFogTiles(around: recorder.lastLocation?.coordinate, radius: fogRadius)
                .map { polygonOverlay(id: "fog:\($0)", coordinate: $0, fill: .fog) }
        }
        result += store.discoveredTiles.prefix(AtlasTheme.maxVisiblePolygons)
            .map { polygonOverlay(id: $0.id, coordinate: $0.coordinate, fill: .discovered) }
        if showsFrontierLayer {
            result += controller.frontierEdgeTileIDs.prefix(AtlasTheme.maxVisiblePolygons).compactMap { id in
                guard let coordinate = engine.parseTileID(id) else { return nil }
                return polygonOverlay(id: id, coordinate: coordinate, fill: .frontier)
            }
        }
        result += controller.claimedSectorBoundaryTileIDs.prefix(AtlasTheme.maxVisiblePolygons).compactMap { id in
            guard let coordinate = engine.parseTileID(id) else { return nil }
            return polygonOverlay(id: "claimed:\(id)", coordinate: coordinate, fill: .claimed)
        }
        if showsFrontierLayer {
            result += controller.targetSectorBoundaryTileIDs.prefix(AtlasTheme.maxVisiblePolygons).compactMap { id in
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

            PolygonAnnotationGroup(overlays.filter { $0.vertices.count >= 3 }) { overlay in
                let ring = Ring(coordinates: overlay.vertices + [overlay.vertices[0]])
                return PolygonAnnotation(polygon: Polygon(outerRing: ring))
                    .fillColor(overlay.fill.color)
                    .fillOpacity(overlay.fill.opacity)
                    .fillOutlineColor(overlay.fill.outline)
            }

            if controller.liveRoute.count > 1 {
                PolylineAnnotation(lineCoordinates: controller.liveRoute)
                    .lineColor(StyleColor(.systemTeal))
                    .lineWidth(4)
                    .lineOpacity(0.85)
            }

            if let treasure = controller.treasureTargetCoordinate {
                MapViewAnnotation(coordinate: treasure) {
                    Button(action: onTreasureTap) {
                        Image(systemName: controller.treasureStore.weeklyVault.isUnlocked ? "lock.open.fill" : "map.fill")
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Circle().fill(Color.yellow))
                    }
                    .buttonStyle(.plain)
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
                ForEvery(store.discoveredTiles.filter { $0.state.markerSymbol != nil }.prefix(AtlasTheme.maxVisibleMarkers)) { tile in
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
        }
        .mapStyle(.standard)
        .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden)))
        .onCameraChanged { _ in
            if followsUser {
                followsUser = false
            }
        }
        .onChange(of: is3DEnabled) { _, enabled in
            position = .followPuck(zoom: 15, pitch: enabled ? 58 : 0)
        }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in
            guard followsUser else { return }
            position = .followPuck(zoom: controller.isRecording ? 16 : 15, pitch: is3DEnabled ? 58 : 0)
        }
        .onAppear {
            overlays = makeOverlays()
            position = .followPuck(zoom: 15, pitch: is3DEnabled ? 58 : 0)
        }
        .onChange(of: store.discoveredTiles) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.frontierEdgeTileIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.claimedSectorBoundaryTileIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.targetSectorBoundaryTileIDs) { _, _ in overlays = makeOverlays() }
        .onChange(of: recorder.lastLocation?.timestamp) { _, _ in overlays = makeOverlays() }
        .onChange(of: controller.isRecording) { _, _ in overlays = makeOverlays() }
        .onChange(of: showsFogLayer) { _, _ in overlays = makeOverlays() }
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

private enum MapboxPolygonFill {
    case discovered, fog, frontier, claimed, target

    var color: StyleColor {
        switch self {
        case .discovered: StyleColor(UIColor(AtlasTheme.teal))
        case .fog: StyleColor(UIColor(AtlasTheme.fogWashFill))
        case .frontier: StyleColor(UIColor(AtlasTheme.frontierWashFill))
        case .claimed: StyleColor(UIColor(AtlasTheme.claimedTerritoryWashFill))
        case .target: StyleColor(UIColor(AtlasTheme.blue.opacity(0.08)))
        }
    }

    var outline: StyleColor {
        switch self {
        case .discovered: StyleColor(UIColor(AtlasTheme.teal))
        case .fog: StyleColor(UIColor(AtlasTheme.fogWashStroke))
        case .frontier: StyleColor(UIColor(AtlasTheme.gold))
        case .claimed: StyleColor(UIColor(AtlasTheme.claimedTerritoryStroke))
        case .target: StyleColor(UIColor(AtlasTheme.targetBoundaryStroke))
        }
    }

    var opacity: Double {
        switch self {
        case .discovered: 0.42
        case .fog: 0.18
        case .frontier: 0.25
        case .claimed: 0.18
        case .target: 0.05
        }
    }
}
