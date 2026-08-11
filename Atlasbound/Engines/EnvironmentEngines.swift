import Foundation

/// Stable, modestly sized biome cells. These cache provider classifications;
/// tile polygons continue to come solely from TileEngine.
struct BiomeCellEngine: Sendable {
    static let span = 6

    func cellID(for tile: TileCoordinate, tileEngine: TileEngine) -> String {
        "biome:\(Int(tileEngine.tileSizeMeters.rounded())):\(floorDiv(tile.q, Self.span)):\(floorDiv(tile.r, Self.span))"
    }

    func representativeTile(for cellID: String) -> TileCoordinate? {
        let parts = cellID.split(separator: ":")
        guard parts.count == 4, parts[0] == "biome", let q = Int(parts[2]), let r = Int(parts[3]) else { return nil }
        return TileCoordinate(q: q * Self.span + Self.span / 2, r: r * Self.span + Self.span / 2)
    }

    private func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        return value % divisor >= 0 ? quotient : quotient - 1
    }
}

struct BiomeSignals: Sendable, Equatable {
    var isWater: Bool = false
    var isRiver: Bool = false
    var isLake: Bool = false
    var isCoast: Bool = false
    var isGreen: Bool = false
    var isForest: Bool = false
    var isPark: Bool = false
    var isUrban: Bool = false
    var isIndustrial: Bool = false
    var isTrail: Bool = false
    var isLandmark: Bool = false
    var elevationMeters: Double = 0
    var slopePercent: Double = 0
}

/// Keeps provider parsing outside game rules. The highest score wins; the fixed
/// priority makes ties deterministic across devices and server refreshes.
struct BiomeClassifier: Sendable {
    func snapshot(cellID: String, signals: BiomeSignals, at date: Date = .now) -> BiomeSnapshot {
        let scores: [AtlasBiome: Int] = [
            .heritage: signals.isLandmark ? 100 : 0,
            .waterside: signals.isWater || signals.isRiver || signals.isLake || signals.isCoast ? 90 : 0,
            .highland: signals.slopePercent >= 8 || signals.elevationMeters >= 220 ? 70 : 0,
            .industrial: signals.isIndustrial ? 60 : 0,
            .green: signals.isGreen || signals.isForest || signals.isPark ? 50 : 0,
            .urban: signals.isUrban ? 40 : 0,
            .open: 1
        ]
        let priority: [AtlasBiome] = [.heritage, .waterside, .highland, .industrial, .green, .urban, .open]
        let primary = priority.max { (scores[$0] ?? 0) < (scores[$1] ?? 0) } ?? .open
        var traits: Set<AtlasBiomeTrait> = []
        if signals.isTrail { traits.insert(.trail) }
        if signals.isPark { traits.insert(.park) }
        if signals.isForest { traits.insert(.forest) }
        if signals.isRiver { traits.insert(.river) }
        if signals.isLake { traits.insert(.lake) }
        if signals.isCoast { traits.insert(.coast) }
        if signals.slopePercent >= 8 { traits.insert(.steep) }
        if signals.isUrban { traits.insert(.dense) }
        if signals.isLandmark { traits.insert(.landmark) }
        return BiomeSnapshot(cellID: cellID, primary: primary, traits: traits, resolvedAt: date, expiresAt: date.addingTimeInterval(12 * 60 * 60))
    }
}

struct EnvironmentalModifierEngine: Sendable {
    static let lowerBound = 0.80
    static let upperBound = 1.35

    func modifiers(biome: BiomeSnapshot?, weather: WeatherSnapshot?) -> EnvironmentalModifiers {
        let weatherModifiers = WeatherEngine().modifiers(for: weather)
        var result = EnvironmentalModifiers(
            cropYield: weatherModifiers.cropYield,
            extractionYield: weatherModifiers.extractionYield,
            solarPower: weatherModifiers.solarPower,
            windPower: weatherModifiers.windPower,
            roadThroughput: weatherModifiers.roadThroughput
        )
        guard let biome else { return bounded(result) }
        switch biome.primary {
        case .green: result.cropYield *= 1.15
        case .waterside:
            result.waterYield *= 1.20
            result.cropYield *= 1.05
        case .highland:
            result.windPower *= 1.15
            result.extractionYield *= 1.10
        case .industrial:
            result.processingSpeed *= 1.15
            result.extractionYield *= 1.05
        case .urban:
            result.roadThroughput *= 1.10
            result.researchSpeed *= 1.05
        case .heritage: result.researchSpeed *= 1.15
        case .open: result.solarPower *= 1.10
        }
        if biome.has(.trail) { result.roadThroughput *= 1.10 }
        return bounded(result)
    }

    private func bounded(_ modifiers: EnvironmentalModifiers) -> EnvironmentalModifiers {
        func clamp(_ value: Double) -> Double { min(Self.upperBound, max(Self.lowerBound, value)) }
        return EnvironmentalModifiers(
            cropYield: clamp(modifiers.cropYield), extractionYield: clamp(modifiers.extractionYield),
            solarPower: clamp(modifiers.solarPower), windPower: clamp(modifiers.windPower),
            roadThroughput: clamp(modifiers.roadThroughput), waterYield: clamp(modifiers.waterYield),
            processingSpeed: clamp(modifiers.processingSpeed), researchSpeed: clamp(modifiers.researchSpeed)
        )
    }
}

struct JourneyEngine: Sendable {
    static let maximumWaypoints = 2_000

    func compact(_ waypoints: [JourneyWaypoint]) -> [JourneyWaypoint] {
        let unique = waypoints.reduce(into: [JourneyWaypoint]()) { result, waypoint in
            guard result.last?.tileID != waypoint.tileID else { return }
            result.append(waypoint)
        }
        guard unique.count > Self.maximumWaypoints else { return unique }
        let lastIndex = unique.count - 1
        return (0..<Self.maximumWaypoints).map { position in
            unique[(position * lastIndex) / (Self.maximumWaypoints - 1)]
        }
    }
}
