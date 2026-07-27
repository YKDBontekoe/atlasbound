import Foundation
import CoreLocation
import MapKit

/// Viewport culling helpers shared by discovery and stats maps.
enum MapOverlayCuller {
    static func cullTiles(
        _ tiles: [WorldTile],
        engine: TileEngine,
        visibleRegion: MKCoordinateRegion?,
        maxCount: Int = AtlasTheme.maxVisiblePolygons
    ) -> [WorldTile] {
        guard let region = visibleRegion else {
            return Array(tiles.prefix(maxCount))
        }

        let padded = region.padded(byFraction: AtlasTheme.viewportPaddingFraction)
        let center = region.center
        var inView: [WorldTile] = []
        inView.reserveCapacity(min(tiles.count, maxCount * 2))

        for tile in tiles {
            let coord = engine.centerCoordinate(for: tile.coordinate)
            guard padded.contains(coord) else { continue }
            inView.append(tile)
        }

        if inView.count <= maxCount {
            return inView
        }

        return Array(
            inView
                .sorted { lhs, rhs in
                    let d0 = approxDistanceSquared(lhs.coordinate, to: center, engine: engine)
                    let d1 = approxDistanceSquared(rhs.coordinate, to: center, engine: engine)
                    if abs(d0 - d1) < 1e-14 {
                        return lhs.state.rawValue > rhs.state.rawValue
                    }
                    return d0 < d1
                }
                .prefix(maxCount)
        )
    }

    static func approxDistanceSquared(
        _ axial: TileCoordinate,
        to center: CLLocationCoordinate2D,
        engine: TileEngine
    ) -> Double {
        let c = engine.centerCoordinate(for: axial)
        let dLat = c.latitude - center.latitude
        let dLon = c.longitude - center.longitude
        return dLat * dLat + dLon * dLon
    }
}

extension MKCoordinateRegion {
    func padded(byFraction fraction: Double) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: span.latitudeDelta * (1 + fraction * 2),
                longitudeDelta: span.longitudeDelta * (1 + fraction * 2)
            )
        )
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let halfLat = span.latitudeDelta / 2
        let halfLon = span.longitudeDelta / 2
        return abs(coordinate.latitude - center.latitude) <= halfLat
            && abs(coordinate.longitude - center.longitude) <= halfLon
    }
}
