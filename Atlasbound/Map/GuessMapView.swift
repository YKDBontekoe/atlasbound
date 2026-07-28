import SwiftUI
import MapKit

/// Tappable world map for placing a Pinpoint guess.
struct GuessMapView: View {
    @Binding var guessCoordinate: CLLocationCoordinate2D?
    var regionConstraint: MKCoordinateRegion?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let coord = guessCoordinate {
                    Annotation("Your Guess", coordinate: coord) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(AtlasTheme.blue)
                    }
                }
            }
            .mapStyle(.standard)
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    guessCoordinate = clamp(coordinate)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                guard let constraint = regionConstraint else { return }
                let clampedCenter = clamp(context.region.center, to: constraint)
                if clampedCenter.latitude != context.region.center.latitude
                    || clampedCenter.longitude != context.region.center.longitude {
                    position = .region(
                        MKCoordinateRegion(center: clampedCenter, span: context.region.span)
                    )
                }
            }
        }
        .onAppear {
            if let region = regionConstraint {
                position = .region(region)
            }
        }
        .onChange(of: regionConstraint?.center.latitude) { _, _ in
            if let region = regionConstraint {
                position = .region(region)
            }
        }
    }

    private func clamp(
        _ coordinate: CLLocationCoordinate2D,
        to region: MKCoordinateRegion? = nil
    ) -> CLLocationCoordinate2D {
        guard let region = region ?? regionConstraint else { return coordinate }
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let minLat = region.center.latitude - halfLat
        let maxLat = region.center.latitude + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon
        return CLLocationCoordinate2D(
            latitude: min(max(coordinate.latitude, minLat), maxLat),
            longitude: min(max(coordinate.longitude, minLon), maxLon)
        )
    }
}
