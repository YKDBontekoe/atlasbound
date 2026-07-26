import SwiftUI
import MapKit

/// Renders discovered hex tiles and an optional live route on a MapKit map.
struct DiscoveryMapView: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TileStore
    @ObservedObject var recorder: ActivityRecorder

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var followsUser = true

    private var engine: TileEngine { store.tileEngine }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(store.discoveredTiles) { tile in
                let vertices = engine.polygon(for: tile.coordinate)
                if vertices.count >= 3 {
                    MapPolygon(coordinates: vertices)
                        .foregroundStyle(fillStyle(for: tile))
                        .stroke(strokeStyle(for: tile), lineWidth: 1)
                }
            }

            if controller.liveRoute.count >= 2 {
                MapPolyline(coordinates: controller.liveRoute)
                    .stroke(.orange.opacity(0.85), lineWidth: 3)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear {
            controller.prepareLocation()
        }
        .onChange(of: recorder.lastLocation?.coordinate.latitude) { _, _ in
            guard followsUser, let location = recorder.lastLocation else { return }
            position = .region(
                MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 600,
                    longitudinalMeters: 600
                )
            )
        }
        .overlay(alignment: .trailing) {
            Button {
                followsUser.toggle()
                if followsUser, let location = recorder.lastLocation {
                    position = .region(
                        MKCoordinateRegion(
                            center: location.coordinate,
                            latitudinalMeters: 600,
                            longitudinalMeters: 600
                        )
                    )
                }
            } label: {
                Image(systemName: followsUser ? "location.fill" : "location")
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
    }

    private func fillStyle(for tile: WorldTile) -> Color {
        switch tile.state {
        case .fogged:
            return .clear
        case .discovered:
            return Color.green.opacity(0.28)
        case .explored:
            return Color.teal.opacity(0.32)
        case .surveyed:
            return Color.cyan.opacity(0.34)
        case .mastered:
            return Color.blue.opacity(0.36)
        case .legendary:
            return Color.indigo.opacity(0.40)
        }
    }

    private func strokeStyle(for tile: WorldTile) -> Color {
        Color.primary.opacity(tile.state == .fogged ? 0 : 0.35)
    }
}

/// Dim fog vignette hint when few tiles are known — discovered polygons punch through visually.
struct FogHintOverlay: View {
    let discoveredCount: Int

    var body: some View {
        if discoveredCount == 0 {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.35),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
    }
}
