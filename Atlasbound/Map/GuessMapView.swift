import SwiftUI
import MapKit

/// Tappable world map for placing a Pinpoint guess. UIViewRepresentable for tap gesture support.
struct GuessMapView: UIViewRepresentable {
    @Binding var guessCoordinate: CLLocationCoordinate2D?
    var regionConstraint: MKCoordinateRegion?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false
        map.delegate = context.coordinator

        if let region = regionConstraint {
            map.setRegion(region, animated: false)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.regionConstraint = regionConstraint
        mapView.removeAnnotations(mapView.annotations)
        if let coord = guessCoordinate {
            let pin = MKPointAnnotation()
            pin.coordinate = coord
            pin.title = "Your Guess"
            mapView.addAnnotation(pin)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: GuessMapView
        var regionConstraint: MKCoordinateRegion?

        init(_ parent: GuessMapView) {
            self.parent = parent
            self.regionConstraint = parent.regionConstraint
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            var coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            coordinate = clamp(coordinate)
            parent.guessCoordinate = coordinate
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard let constraint = regionConstraint else { return }
            let center = clamp(mapView.centerCoordinate, to: constraint)
            if center.latitude != mapView.centerCoordinate.latitude
                || center.longitude != mapView.centerCoordinate.longitude {
                mapView.setCenter(center, animated: false)
            }
        }

        private func clamp(_ coordinate: CLLocationCoordinate2D, to region: MKCoordinateRegion? = nil) -> CLLocationCoordinate2D {
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
}
