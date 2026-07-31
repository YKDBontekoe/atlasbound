import Foundation

/// Derives account-wide levels, rewards, and achievements from canonical atlas progress.
struct ExplorerProgressionEngine: Sendable {
    static let maximumLevel = 50
    static let threeDMapRequiredLevel = 4

    func snapshot(metrics: ExplorerProgressionMetrics) -> ExplorerProgressionSnapshot {
        let totalXP = max(0, metrics.totalXP)
        let level = level(forTotalXP: totalXP)
        let currentThreshold = xpRequired(forLevel: level)
        let nextThreshold = xpRequired(forLevel: min(Self.maximumLevel, level + 1))
        let denominator = max(1, nextThreshold - currentThreshold)
        let progress = level == Self.maximumLevel
            ? 1
            : min(1, Double(totalXP - currentThreshold) / Double(denominator))
        let achievements = achievements(for: metrics)
        let levelTokens = (2...level).reduce(0) { total, unlockedLevel in
            total + tokenReward(forLevel: unlockedLevel)
        }
        let achievementTokens = achievements
            .filter(\.isUnlocked)
            .reduce(0) { $0 + $1.tokenReward }

        return ExplorerProgressionSnapshot(
            totalXP: totalXP,
            level: level,
            title: title(forLevel: level),
            currentLevelXP: currentThreshold,
            nextLevelXP: nextThreshold,
            progressFraction: progress,
            atlasTokens: levelTokens + achievementTokens,
            rewards: rewardTrack(through: Self.maximumLevel),
            achievements: achievements
        )
    }

    func level(forTotalXP totalXP: Int) -> Int {
        let xp = max(0, totalXP)
        var low = 1
        var high = Self.maximumLevel
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

    /// Cumulative curve: early levels arrive quickly, while high ranks remain aspirational.
    func xpRequired(forLevel level: Int) -> Int {
        let rank = max(0, min(Self.maximumLevel, level) - 1)
        return 250 * rank * rank + 750 * rank
    }

    func title(forLevel level: Int) -> String {
        switch level {
        case 40...: "Atlas Legend"
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

    private func tokenReward(forLevel level: Int) -> Int {
        40 + level * 10
    }

    private func rewardTrack(through maximumLevel: Int) -> [ExplorerLevelReward] {
        (2...maximumLevel).flatMap { level -> [ExplorerLevelReward] in
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

    private func achievements(for metrics: ExplorerProgressionMetrics) -> [ExplorerAchievement] {
        [
            .init(
                id: "first-steps",
                name: "First Steps",
                detail: "Discover 10 tiles",
                symbolName: "shoeprints.fill",
                currentValue: metrics.discoveredTiles,
                targetValue: 10,
                tokenReward: 50
            ),
            .init(
                id: "uncharted-hundred",
                name: "Uncharted Hundred",
                detail: "Discover 100 tiles",
                symbolName: "map.fill",
                currentValue: metrics.discoveredTiles,
                targetValue: 100,
                tokenReward: 150
            ),
            .init(
                id: "local-legend",
                name: "Local Legend",
                detail: "Raise 5 tiles to legendary",
                symbolName: "star.circle.fill",
                currentValue: metrics.legendaryTiles,
                targetValue: 5,
                tokenReward: 250
            ),
            .init(
                id: "well-trodden",
                name: "Well Trodden",
                detail: "Record 500 tile visits",
                symbolName: "arrow.trianglehead.2.clockwise.rotate.90",
                currentValue: metrics.totalVisits,
                targetValue: 500,
                tokenReward: 200
            ),
            .init(
                id: "many-roads",
                name: "Many Roads",
                detail: "Stamp 4 activity types",
                symbolName: "figure.mixed.cardio",
                currentValue: metrics.stampedActivityTypes,
                targetValue: 4,
                tokenReward: 200
            ),
            .init(
                id: "expedition-veteran",
                name: "Expedition Veteran",
                detail: "Complete 10 expeditions",
                symbolName: "flag.2.crossed.fill",
                currentValue: metrics.expeditionsCompleted,
                targetValue: 10,
                tokenReward: 300
            ),
            .init(
                id: "seasoned-explorer",
                name: "Seasoned Explorer",
                detail: "Explore on 30 different days",
                symbolName: "calendar.badge.checkmark",
                currentValue: metrics.activeDays,
                targetValue: 30,
                tokenReward: 300
            ),
            .init(
                id: "master-surveyor",
                name: "Master Surveyor",
                detail: "Master 25 tiles",
                symbolName: "scope",
                currentValue: metrics.masteredTiles,
                targetValue: 25,
                tokenReward: 250
            ),
        ]
    }
}
