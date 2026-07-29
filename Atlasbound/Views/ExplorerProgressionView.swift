import SwiftUI

struct ExplorerProgressionView: View {
    let snapshot: ExplorerProgressionSnapshot

    private var nearbyRewards: [ExplorerLevelReward] {
        let lowerBound = max(2, snapshot.level)
        let upperBound = min(ExplorerProgressionEngine.maximumLevel, snapshot.level + 3)
        return snapshot.rewards.filter { ($0.level >= lowerBound && $0.level <= upperBound) || $0.level == snapshot.level }
    }

    var body: some View {
        VStack(spacing: 14) {
            levelCard
            rewardTrackCard
            achievementsCard
        }
    }

    private var levelCard: some View {
        StatSectionCard {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AtlasTheme.blue, AtlasTheme.teal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                        VStack(spacing: 0) {
                            Text("\(snapshot.level)")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                            Text("LEVEL")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.title)
                            .font(.title2.weight(.bold))
                        Text("\(snapshot.totalXP.formatted()) lifetime XP")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Label("\(snapshot.atlasTokens.formatted()) Atlas Tokens", systemImage: "seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtlasTheme.gold)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 6) {
                    ProgressView(value: snapshot.progressFraction)
                        .tint(AtlasTheme.blue)
                        .scaleEffect(y: 1.7)
                    HStack {
                        Text("\(snapshot.xpIntoLevel.formatted()) / \(snapshot.xpNeededForLevel.formatted()) XP")
                        Spacer()
                        if snapshot.level < ExplorerProgressionEngine.maximumLevel {
                            Text("\(snapshot.xpToNextLevel.formatted()) to level \(snapshot.level + 1)")
                        } else {
                            Text("Maximum rank")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("explorerLevelCard")
    }

    private var rewardTrackCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Level rewards")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Automatic unlocks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(nearbyRewards) { reward in
                    let unlocked = snapshot.level >= reward.level
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(unlocked ? AtlasTheme.teal.opacity(0.18) : Color.secondary.opacity(0.10))
                                .frame(width: 38, height: 38)
                            Image(systemName: unlocked ? "checkmark" : reward.symbolName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(unlocked ? AtlasTheme.teal : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Level \(reward.level)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(unlocked ? AtlasTheme.teal : .secondary)
                                Text(reward.name)
                                    .font(.caption.weight(.semibold))
                            }
                            Text(reward.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var achievementsCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Achievements")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(snapshot.achievements.filter(\.isUnlocked).count)/\(snapshot.achievements.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(AtlasTheme.gold)
                }

                ForEach(snapshot.achievements) { achievement in
                    HStack(spacing: 10) {
                        Image(systemName: achievement.symbolName)
                            .foregroundStyle(achievement.isUnlocked ? AtlasTheme.gold : .secondary)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(achievement.name)
                                    .font(.caption.weight(.semibold))
                                Spacer()
                                Text(achievement.isUnlocked ? "+\(achievement.tokenReward)" : "\(min(achievement.currentValue, achievement.targetValue))/\(achievement.targetValue)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(achievement.isUnlocked ? AtlasTheme.gold : .secondary)
                            }
                            Text(achievement.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ProgressView(value: achievement.progressFraction)
                                .tint(achievement.isUnlocked ? AtlasTheme.gold : AtlasTheme.blue)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
