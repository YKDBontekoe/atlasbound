import CoreLocation
import Foundation

/// Keeps live polylines bounded so long car sessions cannot flood MapKit.
enum LiveRouteSimplifier {
    /// Evenly spaced downsample that always keeps the first and last points.
    static func downsample(
        _ coordinates: [CLLocationCoordinate2D],
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard maxPoints >= 2, coordinates.count > maxPoints else { return coordinates }

        var result: [CLLocationCoordinate2D] = []
        result.reserveCapacity(maxPoints)
        result.append(coordinates[0])

        let innerSlots = maxPoints - 2
        let lastIndex = coordinates.count - 1
        for slot in 1...innerSlots {
            let index = (slot * lastIndex) / (innerSlots + 1)
            result.append(coordinates[index])
        }
        result.append(coordinates[lastIndex])
        return result
    }
}
