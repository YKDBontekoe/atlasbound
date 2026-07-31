import Foundation
import CoreLocation
import MapKit

/// Pure aggregation for atlas statistics — area, footprints, and explorer metrics.
struct StatsEngine: Sendable {
    struct MasteryEntry: Sendable {
        let state: TileState
        let count: Int
    }

    struct ActivityFootprintEntry: Sendable {
        let activity: ActivityType
        let tileCount: Int
    }

    struct TerritorySummary: Sendable {
        let totalTileCount: Int
        let totalAreaSquareMeters: Double
    }

    typealias PlaceEntry = RegionLookupEngine.PlaceEntry
    typealias PlacesVisitedSummary = RegionLookupEngine.PlacesVisitedSummary

    // MARK: - Area

    /// Flat-top hex area from flat-to-flat width in meters.
    static func areaSquareMeters(tileCount: Int, flatToFlatMeters: Double) -> Double {
        TileEngine.areaSquareMeters(tileCount: tileCount, flatToFlatMeters: flatToFlatMeters)
    }

    static func totalUnlockedArea(tiles: [WorldTile]) -> TerritorySummary {
        let totalTiles = tiles.filter(\.isDiscovered).count
        return TerritorySummary(
            totalTileCount: totalTiles,
            totalAreaSquareMeters: areaSquareMeters(tileCount: totalTiles, flatToFlatMeters: 20)
        )
    }

    /// Discovered tiles that fall inside any claimed sector.
    static func claimedTerritoryArea(
        state: TerritoryState,
        tiles: [WorldTile],
        tileEngine: TileEngine
    ) -> TerritorySummary {
        guard !state.claims.isEmpty else {
            return TerritorySummary(totalTileCount: 0, totalAreaSquareMeters: 0)
        }
        let sectorEngine = HexSectorEngine()
        let claimedSectors: Set<SectorCoordinate> = Set(
            state.claims.compactMap { sectorEngine.parseSectorID($0.sectorID)?.sector }
        )
        guard !claimedSectors.isEmpty else {
            return TerritorySummary(totalTileCount: 0, totalAreaSquareMeters: 0)
        }
        let count = tiles.filter { tile in
            guard tile.isDiscovered else { return false }
            let sector = sectorEngine.sectorCoordinate(for: tile.coordinate)
            return claimedSectors.contains(sector)
        }.count
        return TerritorySummary(
            totalTileCount: count,
            totalAreaSquareMeters: areaSquareMeters(
                tileCount: count,
                flatToFlatMeters: tileEngine.tileSizeMeters
            )
        )
    }

    // MARK: - Places visited

    /// Aggregate countries / provinces / cities from resolved coarse-cell labels.
    static func placesVisited(
        cellLabels: [String: RegionLookupEngine.PlaceLabels],
        tileCountsByCell: [String: Int]
    ) -> PlacesVisitedSummary {
        RegionLookupEngine.placesVisited(
            cellLabels: cellLabels,
            tileCountsByCell: tileCountsByCell
        )
    }

    static func placesVisited(
        tiles: [WorldTile],
        cellLabels: [String: RegionLookupEngine.PlaceLabels]
    ) -> PlacesVisitedSummary {
        placesVisited(
            cellLabels: cellLabels,
            tileCountsByCell: RegionLookupEngine.tileCountsByCell(tiles: tiles)
        )
    }

    // MARK: - Footprints

    static func activityFootprint(tiles: [WorldTile]) -> [ActivityFootprintEntry] {
        var counts: [ActivityType: Int] = [:]
        for tile in tiles where tile.isDiscovered {
            for activity in tile.activityStamps where activity != .unknown {
                counts[activity, default: 0] += 1
            }
        }
        return ActivityType.selectableCases
            .map { ActivityFootprintEntry(activity: $0, tileCount: counts[$0, default: 0]) }
            .filter { $0.tileCount > 0 }
            .sorted { $0.tileCount > $1.tileCount }
    }

    static func masteryBreakdown(tiles: [WorldTile]) -> [MasteryEntry] {
        var buckets: [TileState: Int] = [:]
        for tile in tiles where tile.isDiscovered {
            buckets[tile.state, default: 0] += 1
        }
        return TileState.allCases
            .filter { $0 != .fogged }
            .map { MasteryEntry(state: $0, count: buckets[$0, default: 0]) }
    }

    static func deepMasteryCount(tiles: [WorldTile]) -> Int {
        tiles.filter { $0.isDiscovered && ($0.state == .mastered || $0.state == .legendary) }.count
    }

    // MARK: - Explorer metrics

    enum BoundingPadding: Sendable {
        /// Scale span by factor with a minimum delta (atlas stats map framing).
        case multiplicative(factor: Double, minDelta: Double)
        /// Add absolute padding with a minimum delta (Home Turf guess map).
        case additive(padding: Double, minDelta: Double)
    }

    static func boundingRegion(
        tileCenters: [CLLocationCoordinate2D],
        padding: BoundingPadding = .multiplicative(factor: 1.35, minDelta: 0.002)
    ) -> MKCoordinateRegion? {
        guard let first = tileCenters.first else { return nil }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for center in tileCenters.dropFirst() {
            minLat = min(minLat, center.latitude)
            maxLat = max(maxLat, center.latitude)
            minLon = min(minLon, center.longitude)
            maxLon = max(maxLon, center.longitude)
        }

        let latSpan: Double
        let lonSpan: Double
        switch padding {
        case .multiplicative(let factor, let minDelta):
            latSpan = max(minDelta, (maxLat - minLat) * factor)
            lonSpan = max(minDelta, (maxLon - minLon) * factor)
        case .additive(let pad, let minDelta):
            latSpan = max(minDelta, maxLat - minLat + pad)
            lonSpan = max(minDelta, maxLon - minLon + pad)
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }

    static func explorerSpanMeters(centers: [CLLocationCoordinate2D]) -> Double {
        guard centers.count >= 2 else { return 0 }
        var minLat = centers[0].latitude
        var maxLat = centers[0].latitude
        var minLon = centers[0].longitude
        var maxLon = centers[0].longitude

        for center in centers.dropFirst() {
            minLat = min(minLat, center.latitude)
            maxLat = max(maxLat, center.latitude)
            minLon = min(minLon, center.longitude)
            maxLon = max(maxLon, center.longitude)
        }

        let nw = CLLocation(latitude: maxLat, longitude: minLon)
        let se = CLLocation(latitude: minLat, longitude: maxLon)
        return nw.distance(from: se)
    }

    static func activeExplorationDays(tiles: [WorldTile]) -> Int {
        var days = Set<String>()
        let calendar = Calendar.current
        for tile in tiles where tile.isDiscovered {
            if let first = tile.firstVisitedAt {
                days.insert(dayKey(for: first, calendar: calendar))
            }
            if let last = tile.lastVisitedAt {
                days.insert(dayKey(for: last, calendar: calendar))
            }
        }
        return days.count
    }

    static func discoveryDateRange(tiles: [WorldTile]) -> (first: Date?, latest: Date?) {
        let dates = tiles.compactMap(\.firstVisitedAt)
        return (dates.min(), dates.max())
    }

    static func tileCenters(tiles: [WorldTile], tileSizeMeters: Int) -> [CLLocationCoordinate2D] {
        let engine = TileEngine(tileSizeMeters: Double(tileSizeMeters))
        return tiles.map { engine.centerCoordinate(for: $0.coordinate) }
    }

    static func dominantActivity(for tile: WorldTile) -> ActivityType? {
        tile.activityStamps
            .filter { $0 != .unknown }
            .sorted { $0.rawValue < $1.rawValue }
            .first
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
