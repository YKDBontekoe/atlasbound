import SwiftUI
import MapKit

/// Tappable world map for placing a GeoGuessr guess. UIViewRepresentable for tap gesture support.
struct GuessMapView: UIViewRepresentable {
    @Binding var guessCoordinate: CLLocationCoordinate2D?

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .standard
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsUserLocation = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        map.addGestureRecognizer(tap)

        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
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

    class Coordinator: NSObject {
        var parent: GuessMapView

        init(_ parent: GuessMapView) {
            self.parent = parent
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.guessCoordinate = coordinate
        }
    }
}
