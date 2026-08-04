import Foundation

/// Derives account-wide levels, rewards, and achievements from canonical atlas progress.
/// Levels are uncapped; L1–50 keep the original quadratic curve for save compatibility.
struct ExplorerProgressionEngine: Sendable {
    /// Legacy soft milestone kept for UI copy that still references the classic arc.
    static let classicArcLevel = 50
    static let threeDMapRequiredLevel = 4

    /// Epithet pools for procedural titles past Atlas Legend.
    private static let epithetNouns = [
        "Ember", "Tide", "Verdant", "Ashen", "Aurora", "Obsidian", "Copper", "Moss",
        "Waystone", "Nimbus", "Hollow", "Gilded", "Storm", "Cinder", "Pearl", "Iron"
    ]
    private static let epithetForms = [
        "Circlet", "Ring", "Spire", "Vault", "Trail", "Codex", "Beacon", "Crown",
        "Lattice", "Horizon", "Archive", "Compass", "Reliquary", "Atlas", "Quill", "Seal"
    ]

    func snapshot(metrics: ExplorerProgressionMetrics) -> ExplorerProgressionSnapshot {
        let totalXP = max(0, metrics.totalXP)
        let level = level(forTotalXP: totalXP)
        let currentThreshold = xpRequired(forLevel: level)
        let nextThreshold = xpRequired(forLevel: level + 1)
        let denominator = max(1, nextThreshold - currentThreshold)
        let progress = min(1, Double(totalXP - currentThreshold) / Double(denominator))
        let achievementFamilies = achievementFamilies(for: metrics)
        let achievements = achievementFamilies.flatMap { visibleTiers(for: $0) }
        let levelTokens = (2...level).reduce(0) { total, unlockedLevel in
            total + tokenReward(forLevel: unlockedLevel)
        }
        let achievementTokens = achievementFamilies.reduce(0) { total, family in
            total + unlockedTokenSum(for: family)
        }

        return ExplorerProgressionSnapshot(
            totalXP: totalXP,
            level: level,
            title: title(forLevel: level),
            currentLevelXP: currentThreshold,
            nextLevelXP: nextThreshold,
            progressFraction: progress,
            atlasTokens: levelTokens + achievementTokens,
            rewards: rewardTrack(through: max(level + 5, Self.classicArcLevel)),
            achievements: achievements
        )
    }

    func level(forTotalXP totalXP: Int) -> Int {
        let xp = max(0, totalXP)
        // Binary search with an expanding high bound — levels are uncapped.
        var low = 1
        var high = 2
        while xpRequired(forLevel: high) <= xp {
            low = high
            high *= 2
            if high > 1_000_000 { break }
        }
        while low < high {
            let middle = (low + high + 1) / 2
            if xpRequired(forLevel: middle) <= xp {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low
    }

    /// Cumulative curve: L1–50 use the classic quadratic; beyond that a steeper continuation.
    func xpRequired(forLevel level: Int) -> Int {
        let rank = max(0, level - 1)
        if level <= Self.classicArcLevel {
            return 250 * rank * rank + 750 * rank
        }
        let base = xpRequired(forLevel: Self.classicArcLevel)
        let over = level - Self.classicArcLevel
        return base + 2_000 * over + 40 * over * over
    }

    func title(forLevel level: Int) -> String {
        switch level {
        case 40...:
            if level <= Self.classicArcLevel {
                return "Atlas Legend"
            }
            return proceduralTitle(forLevel: level)
        case 30...: "Worldweaver"
        case 20...: "Trailblazer"
        case 15...: "Pathfinder"
        case 10...: "Cartographer"
        case 5...: "Wayfinder"
        case 2...: "Scout"
        default: "Wanderer"
        }
    }

    func is3DMapUnlocked(atLevel level: Int) -> Bool {
        level >= Self.threeDMapRequiredLevel
    }

    // MARK: - Private

    private func proceduralTitle(forLevel level: Int) -> String {
        let band = (level - Self.classicArcLevel - 1) / 10
        let seed = StableHash.fnv1a64("explorer-title:\(band)")
        let noun = Self.epithetNouns[Int(seed % UInt64(Self.epithetNouns.count))]
        let form = Self.epithetForms[Int((seed / 97) % UInt64(Self.epithetForms.count))]
        let roman = band + 1
        return "Atlas Legend · \(noun) \(form) \(romanNumeral(roman))"
    }

    private func romanNumeral(_ value: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var remaining = max(1, value)
        var result = ""
        for (n, glyph) in table {
            while remaining >= n {
                result += glyph
                remaining -= n
            }
        }
        return result
    }

    private func tokenReward(forLevel level: Int) -> Int {
        40 + level * 10
    }

    private func rewardTrack(through maximumLevel: Int) -> [ExplorerLevelReward] {
        let end = max(2, maximumLevel)
        return (2...end).flatMap { level -> [ExplorerLevelReward] in
            var rewards = [
                ExplorerLevelReward(
                    level: level,
                    kind: .atlasTokens,
                    name: "\(tokenReward(forLevel: level)) tokens",
                    detail: "Permanent Atlas Token reward",
                    symbolName: "seal.fill"
                )
            ]

            switch level {
            case 2:
                rewards.append(.init(
                    level: level,
                    kind: .mapLayer,
                    name: "Visit Heat",
                    detail: "Highlight the routes you know best",
                    symbolName: "flame.fill"
                ))
            case Self.threeDMapRequiredLevel:
                rewards.append(.init(
                    level: level,
                    kind: .mapStyle,
                    name: "3D Terrain",
                    detail: "Tilt the live atlas into an elevated perspective",
                    symbolName: "cube.fill"
                ))
            default:
                break
            }
            if title(forLevel: level) != title(forLevel: level - 1) {
                rewards.append(.init(
                    level: level,
                    kind: .title,
                    name: title(forLevel: level),
                    detail: "A new rank for your explorer profile",
                    symbolName: "person.crop.circle.badge.checkmark"
                ))
            }
            return rewards
        }
    }

    /// Tiered infinite achievements — UI shows unlocked tiers plus the next locked tier per family.
    private func achievementFamilies(for metrics: ExplorerProgressionMetrics) -> [AchievementFamily] {
        [
            .init(
                id: "first-steps",
                name: "First Steps",
                detailPrefix: "Discover",
                unit: "tiles",
                symbolName: "shoeprints.fill",
                currentValue: metrics.discoveredTiles,
                baseTarget: 10,
                baseTokens: 50
            ),
            .init(
                id: "uncharted",
                name: "Uncharted",
                detailPrefix: "Discover",
                unit: "tiles",
                symbolName: "map.fill",
                currentValue: metrics.discoveredTiles,
                baseTarget: 100,
                baseTokens: 150
            ),
            .init(
                id: "local-legend",
                name: "Local Legend",
                detailPrefix: "Raise",
                unit: "tiles to legendary",
                symbolName: "star.circle.fill",
                currentValue: metrics.legendaryTiles,
                baseTarget: 5,
                baseTokens: 250
            ),
            .init(
                id: "well-trodden",
                name: "Well Trodden",
                detailPrefix: "Record",
                unit: "tile visits",
                symbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                currentValue: metrics.totalVisits,
                baseTarget: 500,
                baseTokens: 200
            ),
            .init(
                id: "many-roads",
                name: "Many Roads",
                detailPrefix: "Stamp",
                unit: "activity types",
                symbolName: "figure.mixed.cardio",
                currentValue: metrics.stampedActivityTypes,
                baseTarget: 4,
                baseTokens: 200,
                maxTier: 2
            ),
            .init(
                id: "expedition-veteran",
                name: "Expedition Veteran",
                detailPrefix: "Complete",
                unit: "expeditions",
                symbolName: "flag.2.crossed.fill",
                currentValue: metrics.expeditionsCompleted,
                baseTarget: 10,
                baseTokens: 300
            ),
            .init(
                id: "seasoned-explorer",
                name: "Seasoned Explorer",
                detailPrefix: "Explore on",
                unit: "different days",
                symbolName: "calendar.badge.checkmark",
                currentValue: metrics.activeDays,
                baseTarget: 30,
                baseTokens: 300
            ),
            .init(
                id: "master-surveyor",
                name: "Master Surveyor",
                detailPrefix: "Master",
                unit: "tiles",
                symbolName: "scope",
                currentValue: metrics.masteredTiles,
                baseTarget: 25,
                baseTokens: 250
            ),
        ]
    }

    private func unlockedTokenSum(for family: AchievementFamily) -> Int {
        var total = 0
        var tier = 1
        let maxTier = family.maxTier ?? 10_000
        while tier <= maxTier {
            let target = family.target(forTier: tier)
            guard family.currentValue >= target else { break }
            total += family.tokens(forTier: tier)
            tier += 1
        }
        return total
    }

    private func visibleTiers(for family: AchievementFamily) -> [ExplorerAchievement] {
        var result: [ExplorerAchievement] = []
        var tier = 1
        let maxTier = family.maxTier ?? 10_000
        while tier <= maxTier {
            let target = family.target(forTier: tier)
            let unlocked = family.currentValue >= target
            let achievement = ExplorerAchievement(
                id: tier == 1 ? family.id : "\(family.id)-t\(tier)",
                name: tier == 1 ? family.name : "\(family.name) \(romanNumeral(tier))",
                detail: "\(family.detailPrefix) \(target) \(family.unit)",
                symbolName: family.symbolName,
                currentValue: family.currentValue,
                targetValue: target,
                tokenReward: family.tokens(forTier: tier)
            )
            if unlocked {
                result.append(achievement)
                tier += 1
                continue
            }
            result.append(achievement)
            break
        }
        // Keep UI bounded: last unlocked + next locked (or just next if none unlocked).
        if result.count <= 2 { return result }
        return Array(result.suffix(2))
    }
}

private struct AchievementFamily {
    let id: String
    let name: String
    let detailPrefix: String
    let unit: String
    let symbolName: String
    let currentValue: Int
    let baseTarget: Int
    let baseTokens: Int
    var maxTier: Int? = nil

    func target(forTier tier: Int) -> Int {
        var value = baseTarget
        for _ in 1..<tier {
            // Escalate ×10 for discovery-style, ×2 for small caps like activity types.
            if baseTarget >= 100 {
                value *= 10
            } else if baseTarget >= 25 {
                value = Int((Double(value) * 4).rounded())
            } else {
                value *= 2
            }
            if value > 1_000_000_000 { return 1_000_000_000 }
        }
        return value
    }

    func tokens(forTier tier: Int) -> Int {
        // Sublinear token growth so infinite tiers stay rewarding but not runaway.
        Int((Double(baseTokens) * (1.0 + 0.35 * Double(tier - 1))).rounded())
    }
}
