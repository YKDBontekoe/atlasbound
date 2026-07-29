import Foundation
import CoreLocation

/// Converts geographic coordinates into stable hexagonal tile IDs.
///
/// Uses flat-top hexes with axial coordinates. Production discovery uses a fixed
/// 20 m width, retained in each tile ID as an integrity check.
struct TileEngine: Sendable {
    let tileSizeMeters: Double

    /// A GPS update can occasionally jump across cities (or continents) while
    /// still reporting a deceptively good horizontal accuracy.  Fill normal
    /// high-speed gaps, but never turn one such outlier into an unbounded row
    /// of persisted tiles.
    static let maximumRouteSegmentMeters = 1_000.0

    /// Distance from hex center to a vertex (redblobgames `size`).
    private var hexSize: Double { tileSizeMeters / sqrt(3.0) }

    private static let earthRadius = 6_378_137.0

    init(tileSizeMeters: Double = TileSizeOption.default.meters) {
        self.tileSizeMeters = tileSizeMeters
    }

    init(option: TileSizeOption) {
        self.tileSizeMeters = option.meters
    }

    // MARK: - Public API

    func tileID(for coordinate: CLLocationCoordinate2D) -> String {
        let axial = axialCoordinate(for: coordinate)
        return Self.makeTileID(q: axial.q, r: axial.r, sizeMeters: tileSizeMeters)
    }

    func axialCoordinate(for coordinate: CLLocationCoordinate2D) -> TileCoordinate {
        let projected = Self.project(coordinate)
        return axialFromMeters(x: projected.x, y: projected.y)
    }

    func worldTileStub(for coordinate: CLLocationCoordinate2D) -> WorldTile {
        let axial = axialCoordinate(for: coordinate)
        let id = Self.makeTileID(q: axial.q, r: axial.r, sizeMeters: tileSizeMeters)
        return WorldTile(id: id, coordinate: axial)
    }

    /// Unique tile IDs touched by a polyline of samples (order preserved, duplicates dropped).
    func tileIDs(along samples: [LocationSample]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for sample in samples {
            let id = tileID(for: sample.coordinate)
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    /// Also walk intermediate hexes between consecutive samples to avoid skipping tiles at speed.
    func tileIDsCoveringRoute(
        _ samples: [LocationSample],
        maximumSegmentMeters: CLLocationDistance = Self.maximumRouteSegmentMeters
    ) -> [String] {
        guard !samples.isEmpty else { return [] }

        var seen = Set<String>()
        var ordered: [String] = []

        func append(_ id: String) {
            if seen.insert(id).inserted {
                ordered.append(id)
            }
        }

        append(tileID(for: samples[0].coordinate))

        for index in 1..<samples.count {
            let previousSample = samples[index - 1]
            let currentSample = samples[index]
            let previous = axialCoordinate(for: previousSample.coordinate)
            let current = axialCoordinate(for: currentSample.coordinate)

            let segmentLength = CLLocation(latitude: previousSample.coordinate.latitude,
                                           longitude: previousSample.coordinate.longitude)
                .distance(from: CLLocation(latitude: currentSample.coordinate.latitude,
                                           longitude: currentSample.coordinate.longitude))
            guard segmentLength <= maximumSegmentMeters else {
                append(Self.makeTileID(q: current.q, r: current.r, sizeMeters: tileSizeMeters))
                continue
            }

            let line = Self.hexLine(from: previous, to: current)
            for coord in line {
                append(Self.makeTileID(q: coord.q, r: coord.r, sizeMeters: tileSizeMeters))
            }
        }

        return ordered
    }

    func centerCoordinate(for axial: TileCoordinate) -> CLLocationCoordinate2D {
        let x = hexSize * (3.0 / 2.0 * Double(axial.q))
        let y = hexSize * (sqrt(3.0) / 2.0 * Double(axial.q) + sqrt(3.0) * Double(axial.r))
        return Self.unproject(x: x, y: y)
    }

    /// Six axial neighbors of a flat-top hex.
    func neighbors(of axial: TileCoordinate) -> [TileCoordinate] {
        Self.neighbors(of: axial)
    }

    /// Flat-top hex area from flat-to-flat width in meters (single tile).
    static func areaSquareMeters(flatToFlatMeters: Double) -> Double {
        guard flatToFlatMeters > 0 else { return 0 }
        return (sqrt(3.0) / 2.0) * flatToFlatMeters * flatToFlatMeters
    }

    /// Total unlocked area for `tileCount` flat-top hexes.
    static func areaSquareMeters(tileCount: Int, flatToFlatMeters: Double) -> Double {
        guard tileCount > 0 else { return 0 }
        return Double(tileCount) * areaSquareMeters(flatToFlatMeters: flatToFlatMeters)
    }

    /// Six axial neighbors of a flat-top hex (static; no tile-size context required).
    static func neighbors(of axial: TileCoordinate) -> [TileCoordinate] {
        neighborOffsets.map { TileCoordinate(q: axial.q + $0.0, r: axial.r + $0.1) }
    }

    /// True when any neighbor is outside the discovered set — the outer rim of claimed territory.
    func isTerritoryPerimeter(_ axial: TileCoordinate, discoveredIDs: Set<String>) -> Bool {
        neighbors(of: axial).contains { neighbor in
            let id = Self.makeTileID(q: neighbor.q, r: neighbor.r, sizeMeters: tileSizeMeters)
            return !discoveredIDs.contains(id)
        }
    }

    /// Perimeter tile IDs among `tiles` (uses the full `discoveredIDs` set so viewport culls stay accurate).
    func territoryPerimeterIDs<S: Sequence>(
        among tiles: S,
        discoveredIDs: Set<String>
    ) -> Set<String> where S.Element == WorldTile {
        Set(
            tiles.compactMap { tile in
                isTerritoryPerimeter(tile.coordinate, discoveredIDs: discoveredIDs) ? tile.id : nil
            }
        )
    }

    /// All axial coordinates within `radius` (inclusive) of `center`.
    func ring(around center: TileCoordinate, radius: Int) -> [TileCoordinate] {
        guard radius > 0 else { return [center] }
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

    static let neighborOffsets: [(Int, Int)] = [
        (1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)
    ]

    /// Six vertices of a flat-top hex around `axial`, in lat/lon (closed ring optional).
    func polygon(for axial: TileCoordinate) -> [CLLocationCoordinate2D] {
        let center = centerCoordinate(for: axial)
        let centerMeters = Self.project(center)
        var vertices: [CLLocationCoordinate2D] = []
        vertices.reserveCapacity(6)

        for i in 0..<6 {
            // Flat-top: angles at 0°, 60°, ...
            let angle = Double.pi / 180.0 * (60.0 * Double(i))
            let vx = centerMeters.x + hexSize * cos(angle)
            let vy = centerMeters.y + hexSize * sin(angle)
            vertices.append(Self.unproject(x: vx, y: vy))
        }
        return vertices
    }

    func parseTileID(_ id: String) -> TileCoordinate? {
        // Format: "hex:{size}:{q}:{r}"
        let parts = id.split(separator: ":")
        guard parts.count == 4, parts[0] == "hex",
              let sizeMeters = Int(parts[1]),
              sizeMeters == Int(tileSizeMeters.rounded()),
              let q = Int(parts[2]), let r = Int(parts[3]) else {
            return nil
        }
        let coordinate = TileCoordinate(q: q, r: r)
        guard id == Self.makeTileID(q: q, r: r, sizeMeters: tileSizeMeters) else {
            return nil
        }
        return coordinate
    }

    static func makeTileID(q: Int, r: Int, sizeMeters: Double) -> String {
        let sizeKey = Int(sizeMeters.rounded())
        return "hex:\(sizeKey):\(q):\(r)"
    }

    // MARK: - Projection (Web Mercator meters)

    static func project(_ coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let lat = min(max(coordinate.latitude, -85.05112878), 85.05112878)
        let lon = coordinate.longitude
        let x = earthRadius * lon * .pi / 180.0
        let y = earthRadius * log(tan(.pi / 4.0 + lat * .pi / 360.0))
        return (x, y)
    }

    static func unproject(x: Double, y: Double) -> CLLocationCoordinate2D {
        let lon = x / earthRadius * 180.0 / .pi
        let lat = (2.0 * atan(exp(y / earthRadius)) - .pi / 2.0) * 180.0 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Hex math (flat-top axial)

    private func axialFromMeters(x: Double, y: Double) -> TileCoordinate {
        let q = (2.0 / 3.0 * x) / hexSize
        let r = (-1.0 / 3.0 * x + sqrt(3.0) / 3.0 * y) / hexSize
        return Self.cubeRound(q: q, r: r)
    }

    private static func cubeRound(q: Double, r: Double) -> TileCoordinate {
        let cq = q
        let cr = r
        let cs = -q - r

        var rq = round(cq)
        var rr = round(cr)
        let rs = round(cs)

        let qDiff = abs(rq - cq)
        let rDiff = abs(rr - cr)
        let sDiff = abs(rs - cs)

        if qDiff > rDiff && qDiff > sDiff {
            rq = -rr - rs
        } else if rDiff > sDiff {
            rr = -rq - rs
        }

        return TileCoordinate(q: Int(rq), r: Int(rr))
    }

    /// Hexes on a line between two axial coords (inclusive).
    static func hexLine(from a: TileCoordinate, to b: TileCoordinate) -> [TileCoordinate] {
        let n = hexDistance(a, b)
        if n == 0 { return [a] }

        var results: [TileCoordinate] = []
        results.reserveCapacity(n + 1)
        for i in 0...n {
            let t = Double(i) / Double(n)
            let q = Double(a.q) + (Double(b.q) - Double(a.q)) * t
            let r = Double(a.r) + (Double(b.r) - Double(a.r)) * t
            results.append(cubeRound(q: q, r: r))
        }
        return results
    }

    static func hexDistance(_ a: TileCoordinate, _ b: TileCoordinate) -> Int {
        let dq = a.q - b.q
        let dr = a.r - b.r
        let ds = a.s - b.s
        return max(abs(dq), abs(dr), abs(ds))
    }
}
