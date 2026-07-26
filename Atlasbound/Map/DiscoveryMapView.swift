import SwiftUI
import MapKit

/// Renders discovered hex tiles, optional fog wash, and the live route on MapKit.
struct DiscoveryMapView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var recorder: ActivityRecorder

    @Binding var position: MapCameraPosition
    @Binding var followsUser: Bool

    var showFogWash: Bool = false
    var showTileMarkers: Bool = true

    private var engine: TileEngine { store.tileEngine }

    private var markerTiles: [WorldTile] {
        guard showTileMarkers else { return [] }
        // Cap annotations for performance; prefer higher ranks.
        let ranked = store.discoveredTiles.sorted { $0.state.rawValue > $1.state.rawValue }
        return Array(ranked.prefix(80))
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            if showFogWash {
                ForEach(fogCoordinates, id: \.self) { axial in
                    let vertices = engine.polygon(for: axial)
                    if vertices.count >= 3 {
                        MapPolygon(coordinates: vertices)
                            .foregroundStyle(Color.white.opacity(0.52))
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    }
                }
            }

            ForEach(store.discoveredTiles) { tile in
                let vertices = engine.polygon(for: tile.coordinate)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(tile.state.mapFill)
                        .stroke(tile.state.mapStroke, lineWidth: tile.state == .mastered || tile.state == .legendary ? 2 : 1)
                }
            }

            ForEach(markerTiles) { tile in
                if let symbol = tile.state.markerSymbol {
                    Annotation("", coordinate: engine.centerCoordinate(for: tile.coordinate), anchor: .center) {
                        TileMarkerView(symbol: symbol, tint: tile.state.markerTint)
                    }
                }
            }

            if controller.liveRoute.count >= 2 {
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(.white.opacity(0.9), lineWidth: 7)
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(AtlasTheme.blue, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {
            MapCompass()
        }
        .onAppear {
            controller.prepareLocation()
        }
        .onChange(of: recorder.lastLocation?.coordinate.latitude) { _, _ in
            guard followsUser, let location = recorder.lastLocation else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                position = .region(
                    MKCoordinateRegion(
                        center: location.coordinate,
                        latitudinalMeters: controller.isRecording ? 450 : 700,
                        longitudinalMeters: controller.isRecording ? 450 : 700
                    )
                )
            }
        }
    }

    private var fogCoordinates: [TileCoordinate] {
        controller.nearbyFogTiles(around: recorder.lastLocation?.coordinate, radius: 6)
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
