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
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let searchMeters = TreasureConstants.landmarkSearchMeters

        for term in searchTerms {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: searchMeters,
                longitudinalMeters: searchMeters
            )
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            for item in response.mapItems {
                let targetCoordinate = item.placemark.coordinate
                guard CLLocationCoordinate2DIsValid(targetCoordinate) else { continue }
                let distance = origin.distance(
                    from: CLLocation(latitude: targetCoordinate.latitude, longitude: targetCoordinate.longitude)
                )
                guard distance >= TreasureConstants.minTargetMeters,
                      distance <= TreasureConstants.maxTargetMeters else { continue }
                let tileID = tileEngine.tileID(for: targetCoordinate)
                guard seenTileIDs.insert(tileID).inserted else { continue }
                let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let name, !name.isEmpty else { continue }
                results.append(
                    (
                        target: LandmarkTarget(
                            id: "landmark:\(tileID)",
                            tileID: tileID,
                            name: name,
                            category: term.capitalized,
                            clue: "A hidden atlas mark waits near \(name), far along the frontier.",
                            isFallback: false,
                            distanceMeters: distance
                        ),
                        distance: distance
                    )
                )
            }
        }

        return spreadTargets(from: results, count: count)
    }

    /// Prefer targets spread across distance rather than the nearest cluster.
    /// Returns nearer half first (direct slots), farther half last (detour slots).
    private func spreadTargets(
        from candidates: [(target: LandmarkTarget, distance: CLLocationDistance)],
        count: Int
    ) -> [LandmarkTarget] {
        let sorted = candidates.sorted { $0.distance < $1.distance }
        guard count > 0 else { return [] }
        guard sorted.count > count else { return sorted.map(\.target) }

        var pickedIndices = Set<Int>()
        var picked: [(target: LandmarkTarget, distance: CLLocationDistance)] = []
        let last = sorted.count - 1
        for slot in 0..<count {
            let fraction = count == 1 ? 0.0 : Double(slot) / Double(count - 1)
            var index = Int((fraction * Double(last)).rounded())
            if pickedIndices.contains(index) {
                if let open = (0...last).first(where: { !pickedIndices.contains($0) }) {
                    index = open
                } else {
                    break
                }
            }
            pickedIndices.insert(index)
            picked.append(sorted[index])
        }

        // Fill any shortfall from remaining nearest-unpicked.
        if picked.count < count {
            for (index, candidate) in sorted.enumerated() where !pickedIndices.contains(index) {
                picked.append(candidate)
                pickedIndices.insert(index)
                if picked.count >= count { break }
            }
        }

        return picked.sorted { $0.distance < $1.distance }.map(\.target)
    }
}
