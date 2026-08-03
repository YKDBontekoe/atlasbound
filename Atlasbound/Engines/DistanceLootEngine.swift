import Foundation

/// Distance bands that scale rare loot quality for treasures and field finds.
enum DistanceLootBand: Int, Codable, Sendable, CaseIterable, Comparable {
    case local
    case mid
    case far
    case expedition

    static func < (lhs: DistanceLootBand, rhs: DistanceLootBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .local: "Local"
        case .mid: "Mid"
        case .far: "Far"
        case .expedition: "Expedition"
        }
    }
}

enum DistanceLootConstants {
    static let midThresholdMeters: Double = 1_500
    static let farThresholdMeters: Double = 4_000
    static let expeditionThresholdMeters: Double = 8_000
}

/// Pure helpers for distance-banded loot quality.
struct DistanceLootEngine: Sendable {
    static func band(meters: Double) -> DistanceLootBand {
        let distance = max(0, meters)
        if distance >= DistanceLootConstants.expeditionThresholdMeters { return .expedition }
        if distance >= DistanceLootConstants.farThresholdMeters { return .far }
        if distance >= DistanceLootConstants.midThresholdMeters { return .mid }
        return .local
    }

    static func meters(hexDistance: Int, tileSizeMeters: Double) -> Double {
        Double(max(0, hexDistance)) * tileSizeMeters
    }

    static func band(hexDistance: Int, tileSizeMeters: Double) -> DistanceLootBand {
        band(meters: meters(hexDistance: hexDistance, tileSizeMeters: tileSizeMeters))
    }

    /// Subtracted from a 0…99 rarity roll so lower rolls (better loot) become more likely farther out.
    static func rarityRollBonus(for band: DistanceLootBand) -> Int {
        switch band {
        case .local: 0
        case .mid: 10
        case .far: 25
        case .expedition: 40
        }
    }

    static func rareSparkChancePercent(for band: DistanceLootBand) -> Int {
        switch band {
        case .local: FieldFindConstants.rareSparkChancePercent
        case .mid: 12
        case .far: 18
        case .expedition: 24
        }
    }

    /// Weight multiplier for uncommon-or-better field-find table entries.
    static func uncommonWeightMultiplier(for band: DistanceLootBand) -> Int {
        switch band {
        case .local: 1
        case .mid: 2
        case .far: 3
        case .expedition: 4
        }
    }

    static func trailCompletionXP(for band: DistanceLootBand) -> Int {
        switch band {
        case .local: 75
        case .mid: 90
        case .far: 110
        case .expedition: 130
        }
    }

    static func vaultCompletionXP(for band: DistanceLootBand) -> Int {
        switch band {
        case .local: 150
        case .mid: 175
        case .far: 200
        case .expedition: 230
        }
    }

    /// Axial tile at exact hex radius along a direction (avoids filling large disks).
    static func tileAtRadius(
        around center: TileCoordinate,
        radius: Int,
        direction: Int
    ) -> TileCoordinate {
        guard radius > 0 else { return center }
        let offsets = TileEngine.neighborOffsets
        let offset = offsets[((direction % offsets.count) + offsets.count) % offsets.count]
        return TileCoordinate(q: center.q + offset.0 * radius, r: center.r + offset.1 * radius)
    }

    /// Point on the hex ring perimeter (6 × radius slots) without allocating the full disk.
    static func tileOnRing(
        around center: TileCoordinate,
        radius: Int,
        index: Int
    ) -> TileCoordinate {
        guard radius > 0 else { return center }
        let perimeter = 6 * radius
        var remaining = ((index % perimeter) + perimeter) % perimeter
        // Standard axial ring: start at direction 4 × radius, then walk sides 0…5.
        var axial = tileAtRadius(around: center, radius: radius, direction: 4)
        for side in 0..<6 {
            let walk = TileEngine.neighborOffsets[side]
            if remaining < radius {
                return TileCoordinate(q: axial.q + walk.0 * remaining, r: axial.r + walk.1 * remaining)
            }
            axial = TileCoordinate(q: axial.q + walk.0 * radius, r: axial.r + walk.1 * radius)
            remaining -= radius
        }
        return axial
    }
}
