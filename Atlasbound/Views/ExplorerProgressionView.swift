import SwiftUI

struct ExplorerProgressionView: View {
    let snapshot: ExplorerProgressionSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllAchievements = false

    private var isMaximumLevel: Bool {
        snapshot.level == ExplorerProgressionEngine.maximumLevel
    }

    private var nextLevelRewards: [ExplorerLevelReward] {
        let level = isMaximumLevel ? snapshot.level : snapshot.level + 1
        return snapshot.rewards.filter { $0.level == level }
    }

    private var unlockedAchievementCount: Int {
        snapshot.achievements.filter(\.isUnlocked).count
    }

    private var priorityAchievements: [ExplorerAchievement] {
        let locked = snapshot.achievements
            .filter { !$0.isUnlocked }
            .sorted {
                if $0.progressFraction == $1.progressFraction {
                    return $0.targetValue < $1.targetValue
                }
                return $0.progressFraction > $1.progressFraction
            }

        if locked.isEmpty {
            return Array(snapshot.achievements.prefix(3))
        }
        return Array(locked.prefix(3))
    }

    private var visibleAchievements: [ExplorerAchievement] {
        showsAllAchievements ? snapshot.achievements : priorityAchievements
    }

    var body: some View {
        VStack(spacing: 14) {
            explorerHero
            nextLevelCard
            achievementsCard
        }
    }

    private var explorerHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                levelMedallion

                VStack(alignment: .leading, spacing: 3) {
                    Text("EXPLORER RANK")
                        .font(.caption2.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(snapshot.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Level \(snapshot.level) of \(ExplorerProgressionEngine.maximumLevel)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                }

                Spacer(minLength: 0)

                AtlasArtMark(name: "ExplorerMark", size: 62)
            }

            VStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                        Capsule()
                            .fill(.white)
                            .frame(width: proxy.size.width * snapshot.progressFraction)
                    }
                }
                .frame(height: 8)
                .animation(
                    AtlasMotion.optional(AtlasMotion.panel, reduceMotion: reduceMotion),
                    value: snapshot.progressFraction
                )

                HStack {
                    if isMaximumLevel {
                        Text("Maximum rank reached")
                    } else {
                        Text("\(snapshot.xpIntoLevel.formatted()) / \(snapshot.xpNeededForLevel.formatted()) XP")
                        Spacer()
                        Text("\(snapshot.xpToNextLevel.formatted()) XP to level \(snapshot.level + 1)")
                    }
                }
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 8) {
                heroMetric(
                    value: snapshot.totalXP.formatted(),
                    label: "Lifetime XP",
                    symbol: "sparkles"
                )
                heroMetric(
                    value: snapshot.atlasTokens.formatted(),
                    label: "Tokens",
                    symbol: "seal.fill"
                )
                heroMetric(
                    value: "\(unlockedAchievementCount)/\(snapshot.achievements.count)",
                    label: "Badges",
                    symbol: "medal.fill"
                )
            }
        }
        .padding(18)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.10, green: 0.24, blue: 0.52),
                                AtlasTheme.blue,
                                AtlasTheme.teal.opacity(0.88),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .stroke(.white.opacity(0.09), lineWidth: 24)
                    .frame(width: 150, height: 150)
                    .offset(x: 48, y: -70)
                    .accessibilityHidden(true)
            }
            .shadow(color: AtlasTheme.blue.opacity(0.25), radius: 16, y: 7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("explorerLevelCard")
    }

    private var levelMedallion: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.16))
            Circle()
                .stroke(.white.opacity(0.32), lineWidth: 1)
            VStack(spacing: -2) {
                Text("\(snapshot.level)")
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                Text("LEVEL")
                    .font(.system(size: 8, weight: .heavy))
                    .tracking(0.8)
            }
            .foregroundStyle(.white)
        }
        .frame(width: 70, height: 70)
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityHidden(true)
    }

    private func heroMetric(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var nextLevelCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    sectionIcon(
                        symbol: isMaximumLevel ? "crown.fill" : "flag.checkered",
                        color: isMaximumLevel ? AtlasTheme.gold : AtlasTheme.blue
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isMaximumLevel ? "Reward track complete" : "Next level")
                            .font(.subheadline.weight(.semibold))
                        Text(
                            isMaximumLevel
                                ? "You’ve reached the summit"
                                : "\(snapshot.xpToNextLevel.formatted()) XP remaining"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !isMaximumLevel {
                        Text("LVL \(snapshot.level + 1)")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(AtlasTheme.blue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(AtlasTheme.blue.opacity(0.1), in: Capsule())
                    }
                }

                if nextLevelRewards.isEmpty {
                    Text("Every road from here adds to your legend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(nextLevelRewards) { reward in
                        HStack(spacing: 10) {
                            Image(systemName: reward.symbolName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    reward.kind == .atlasTokens ? AtlasTheme.gold : AtlasTheme.teal
                                )
                                .frame(width: 28, height: 28)
                                .background(
                                    (reward.kind == .atlasTokens ? AtlasTheme.gold : AtlasTheme.teal)
                                        .opacity(0.12),
                                    in: Circle()
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(reward.name)
                                    .font(.caption.weight(.semibold))
                                Text(reward.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var achievementsCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    sectionIcon(symbol: "medal.fill", color: AtlasTheme.gold)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Achievements")
                            .font(.subheadline.weight(.semibold))
                        Text("\(unlockedAchievementCount) of \(snapshot.achievements.count) earned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !snapshot.achievements.isEmpty {
                        Text("\(unlockedAchievementCount)/\(snapshot.achievements.count)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(AtlasTheme.gold)
                    }
                }

                ForEach(Array(visibleAchievements.enumerated()), id: \.element.id) { index, achievement in
                    if index > 0 {
                        Divider()
                    }
                    achievementRow(achievement)
                }

                if snapshot.achievements.count > priorityAchievements.count {
                    Button {
                        AtlasMotion.withOptionalAnimation(AtlasMotion.panel, reduceMotion: reduceMotion) {
                            showsAllAchievements.toggle()
                        }
                    } label: {
                        HStack {
                            Text(showsAllAchievements ? "Show priority goals" : "View all achievements")
                            Spacer()
                            Image(systemName: showsAllAchievements ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.blue)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("toggleAllAchievements")
                }
            }
        }
    }

    private func achievementRow(_ achievement: ExplorerAchievement) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(
                        (achievement.isUnlocked ? AtlasTheme.gold : AtlasTheme.blue)
                            .opacity(0.12)
                    )
                Image(systemName: achievement.isUnlocked ? "checkmark" : achievement.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(achievement.isUnlocked ? AtlasTheme.gold : AtlasTheme.blue)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.name)
                            .font(.caption.weight(.semibold))
                        Text(achievement.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Text(
                        achievement.isUnlocked
                            ? "+\(achievement.tokenReward)"
                            : "\(min(achievement.currentValue, achievement.targetValue))/\(achievement.targetValue)"
                    )
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(achievement.isUnlocked ? AtlasTheme.gold : .secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(achievement.isUnlocked ? AtlasTheme.gold : AtlasTheme.blue)
                            .frame(width: proxy.size.width * achievement.progressFraction)
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionIcon(symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 36, height: 36)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
