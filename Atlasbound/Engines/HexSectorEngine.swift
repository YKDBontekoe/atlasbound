import Foundation
import CoreLocation

/// Groups each tile grid into deterministic coarse sectors derived at runtime.
struct HexSectorEngine: Sendable {
    static let span = 36

    // MARK: - Sector identity

    func sectorCoordinate(for tile: TileCoordinate) -> SectorCoordinate {
        nearestSectorCenter(for: tile)
    }

    func sectorID(for sector: SectorCoordinate, sizeMeters: Double) -> String {
        Self.makeSectorID(q: sector.q, r: sector.r, sizeMeters: sizeMeters)
    }

    func sectorID(for tile: TileCoordinate, sizeMeters: Double) -> String {
        sectorID(for: sectorCoordinate(for: tile), sizeMeters: sizeMeters)
    }

    static func makeSectorID(q: Int, r: Int, sizeMeters: Double) -> String {
        let sizeKey = Int(sizeMeters.rounded())
        return "sector:\(sizeKey):\(q):\(r)"
    }

    func parseSectorID(_ id: String) -> (sector: SectorCoordinate, sizeMeters: Int)? {
        let parts = id.split(separator: ":")
        guard parts.count == 4, parts[0] == "sector",
              let size = Int(parts[1]),
              let q = Int(parts[2]),
              let r = Int(parts[3]) else {
            return nil
        }
        return (SectorCoordinate(q: q, r: r), size)
    }

    // MARK: - Membership & boundaries

    /// Axial tile at the coarse lattice center for a sector.
    func centerTile(for sector: SectorCoordinate) -> TileCoordinate {
        TileCoordinate(q: sector.q * Self.span, r: sector.r * Self.span)
    }

    /// All tile coordinates assigned to `sector` within the sampling radius.
    func tiles(in sector: SectorCoordinate) -> Set<TileCoordinate> {
        let center = centerTile(for: sector)
        var members: Set<TileCoordinate> = []
        for tile in sampleTiles(around: center, radius: Self.span + 2) {
            if sectorCoordinate(for: tile) == sector {
                members.insert(tile)
            }
        }
        return members
    }

    /// Tiles on the sector boundary (have a neighbor in a different sector).
    func boundaryTiles(for sector: SectorCoordinate) -> Set<TileCoordinate> {
        let members = tiles(in: sector)
        var boundary: Set<TileCoordinate> = []
        for tile in members {
            let neighbors = TileEngine.neighbors(of: tile)
            if neighbors.contains(where: { sectorCoordinate(for: $0) != sector }) {
                boundary.insert(tile)
            }
        }
        return boundary
    }

    /// Monotone-chain hull for a small sector footprint. Longitude and latitude
    /// are intentionally treated as planar coordinates here: the largest sector
    /// spans well below a kilometre, where that approximation is stable.
    func convexHull(of coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        let sorted = coordinates.sorted { lhs, rhs in
            lhs.longitude == rhs.longitude ? lhs.latitude < rhs.latitude : lhs.longitude < rhs.longitude
        }
        guard sorted.count > 2 else { return sorted }

        func cross(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ c: CLLocationCoordinate2D) -> Double {
            (b.longitude - a.longitude) * (c.latitude - a.latitude)
                - (b.latitude - a.latitude) * (c.longitude - a.longitude)
        }

        var lower: [CLLocationCoordinate2D] = []
        for point in sorted {
            while lower.count >= 2,
                  cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CLLocationCoordinate2D] = []
        for point in sorted.reversed() {
            while upper.count >= 2,
                  cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        return Array(lower.dropLast() + upper.dropLast())
    }

    func completionFraction(
        sector: SectorCoordinate,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine
    ) -> Double {
        let members = tiles(in: sector)
        guard !members.isEmpty else { return 0 }
        let discovered = members.filter { tile in
            let id = TileEngine.makeTileID(q: tile.q, r: tile.r, sizeMeters: tileEngine.tileSizeMeters)
            return discoveredTileIDs.contains(id)
        }.count
        return Double(discovered) / Double(members.count)
    }

    func completionPercent(
        sector: SectorCoordinate,
        discoveredTileIDs: Set<String>,
        tileEngine: TileEngine
    ) -> Int {
        Int((completionFraction(sector: sector, discoveredTileIDs: discoveredTileIDs, tileEngine: tileEngine) * 100).rounded())
    }

    // MARK: - Sector navigation

    func neighborSector(_ sector: SectorCoordinate, directionIndex: Int) -> SectorCoordinate {
        let offset = TileEngine.neighborOffsets[directionIndex % 6]
        return SectorCoordinate(q: sector.q + offset.0, r: sector.r + offset.1)
    }

    func sectorDistance(from origin: SectorCoordinate, to target: SectorCoordinate) -> Int {
        let a = centerTile(for: origin)
        let b = centerTile(for: target)
        return max(1, (TileEngine.hexDistance(a, b) + Self.span / 2) / Self.span)
    }

    func sectorAt(distance: Int, from origin: SectorCoordinate, directionIndex: Int) -> SectorCoordinate {
        var current = origin
        for _ in 0..<distance {
            current = neighborSector(current, directionIndex: directionIndex)
        }
        return current
    }

    // MARK: - Display

    func displayName(for sector: SectorCoordinate) -> String {
        let catalog = [
            "Amber Reach", "Birch Crossing", "Cedar Vale", "Driftwood Bend",
            "Ember Ridge", "Frost Hollow", "Granite Span", "Harbor Watch",
            "Ironwood Gate", "Juniper Line", "Kestrel Pass", "Linden Shore",
            "Mistral Step", "Northwind Shelf", "Oakfall Terrace", "Pinecrest",
            "Quartz Narrows", "Rivergate", "Stonebrook", "Thistle Moor",
            "Upland Trace", "Verdant Shelf", "Willow Fen", "Yarrow Bluffs",
        ]
        let index = abs(sector.q &* 31_337 ^ sector.r &* 1_009) % catalog.count
        return catalog[index]
    }

    // MARK: - Private

    private func nearestSectorCenter(for tile: TileCoordinate) -> SectorCoordinate {
        let roughQ = tile.q >= 0 ? tile.q / Self.span : (tile.q - Self.span + 1) / Self.span
        let roughR = tile.r >= 0 ? tile.r / Self.span : (tile.r - Self.span + 1) / Self.span

        var best: (SectorCoordinate, Int)?
        for dQ in -1...1 {
            for dR in -1...1 {
                let candidate = SectorCoordinate(q: roughQ + dQ, r: roughR + dR)
                let center = centerTile(for: candidate)
                let distance = TileEngine.hexDistance(tile, center)
                if let current = best {
                    if distance < current.1 || (distance == current.1 && candidate < current.0) {
                        best = (candidate, distance)
                    }
                } else {
                    best = (candidate, distance)
                }
            }
        }
        return best?.0 ?? SectorCoordinate(q: 0, r: 0)
    }

    private func sampleTiles(around center: TileCoordinate, radius: Int) -> [TileCoordinate] {
        var results: [TileCoordinate] = []
        for q in -radius...radius {
            let r1 = max(-radius, -q - radius)
            let r2 = min(radius, -q + radius)
            for r in r1...r2 {
                results.append(TileCoordinate(q: center.q + q, r: center.r + r))
            }
        }
        return results
    }

}
