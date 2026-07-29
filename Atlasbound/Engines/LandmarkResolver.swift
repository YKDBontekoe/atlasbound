import Foundation
import MapKit

protocol LandmarkResolving: Sendable {
    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine,
        count: Int
    ) async -> [LandmarkTarget]
}

extension LandmarkResolving {
    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine
    ) async -> [LandmarkTarget] {
        await targets(
            near: coordinate,
            tileEngine: tileEngine,
            count: TreasureConstants.stagesPerTrail * 2
        )
    }
}

struct LandmarkResolver: LandmarkResolving, Sendable {
    private let searchTerms = ["park", "library", "monument", "museum", "public art", "historic site"]

    func targets(
        near coordinate: CLLocationCoordinate2D,
        tileEngine: TileEngine,
        count: Int = TreasureConstants.stagesPerTrail * 2
    ) async -> [LandmarkTarget] {
        var results: [(target: LandmarkTarget, distance: CLLocationDistance)] = []
        var seenTileIDs = Set<String>()
        for term in searchTerms where results.count < count {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 3_000,
                longitudinalMeters: 3_000
            )
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                let targetCoordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(targetCoordinate) else { continue }
                let tileID = tileEngine.tileID(for: targetCoordinate)
                guard seenTileIDs.insert(tileID).inserted else { continue }
                guard await isWalkable(from: coordinate, to: item) else { continue }
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let name, !name.isEmpty else { continue }
                results.append(
                    (
                        target: LandmarkTarget(
                        id: "landmark:\(tileID)",
                        tileID: tileID,
                        name: name,
                        category: term.capitalized,
                        clue: "A hidden atlas mark waits near \(name).",
                        isFallback: false
                        ),
                        distance: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                            .distance(from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude))
                    )
                )
                if results.count >= count { break }
            }
        }
        return results.sorted { $0.distance < $1.distance }.map(\.target)
    }

    private func isWalkable(from coordinate: CLLocationCoordinate2D, to item: MKMapItem) async -> Bool {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.destination = item
        request.transportType = .walking
        guard let response = try? await MKDirections(request: request).calculate(),
              let route = response.routes.first else { return false }
        return route.distance >= 80 && route.distance <= 5_000
    }
}
