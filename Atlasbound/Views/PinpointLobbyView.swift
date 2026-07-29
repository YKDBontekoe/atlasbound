import SwiftUI

/// Lobby screen: mode picker, stats, Game Center sign-in, recent games.
struct PinpointLobbyView: View {
    @ObservedObject var controller: PinpointController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                    .staggeredAppear(index: 0)
                modePicker
                    .staggeredAppear(index: 1)
                statsCard
                    .staggeredAppear(index: 2)
                gameCenterSection
                    .staggeredAppear(index: 3)

                if let error = controller.preparationError {
                    VStack(spacing: 8) {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(AtlasTheme.finishRed)
                            .multilineTextAlignment(.center)
                        Button("Try Worldwide again") {
                            controller.startNewGame(mode: .worldwide)
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .transition(.opacity)
                }

                if let error = controller.gameCenterManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.finishRed)
                }

                if !controller.store.gameHistory.isEmpty {
                    recentGamesSection
                        .staggeredAppear(index: 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 8) {
            AtlasArtMark(name: "PinpointMark", size: 104)
            Text("Pinpoint")
                .font(.largeTitle.bold())
            Text("Guess your location from Look Around")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var modePicker: some View {
        VStack(spacing: 12) {
            modeCard(
                mode: .worldwide,
                highScore: controller.store.highScore(for: .worldwide),
                enabled: true
            ) {
                controller.startNewGame(mode: .worldwide)
            }

            modeCard(
                mode: .homeTurf,
                highScore: controller.store.highScore(for: .homeTurf),
                enabled: controller.homeTurfUnlocked,
                footer: { homeTurfFooter }
            ) {
                controller.startNewGame(mode: .homeTurf)
            }
        }
    }

    @ViewBuilder
    private var homeTurfFooter: some View {
        if controller.homeTurfUnlocked {
            let area = controller.unlockedAreaM2
            let tier = PinpointAtlasTier.tier(for: area)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(PinpointScoring.formatArea(area))
                        .font(.caption.weight(.semibold))
                    Text("unlocked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tier.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AtlasTheme.gold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AtlasTheme.gold.opacity(0.12), in: Capsule())
                }
                Text("Stricter scoring — improves as your atlas grows.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Discover \(controller.homeTurfTilesNeeded) more tiles to unlock.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func modeCard<Footer: View>(
        mode: PinpointGameMode,
        highScore: Int,
        enabled: Bool,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(highScore)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text("best")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            footer()

            Button(action: {
                AtlasHaptics.select()
                action()
            }) {
                HStack {
                    Image(systemName: enabled ? "play.fill" : "lock.fill")
                    Text(enabled ? "Play \(mode.displayName)" : "\(mode.displayName) locked")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(TintedGlassButtonStyle(tint: mode == .homeTurf ? AtlasTheme.gold : AtlasTheme.blue, shape: .capsule))
            .disabled(!enabled || controller.phase == .preparing)
            .opacity(enabled ? 1 : 0.45)
            .accessibilityValue(enabled ? "Available" : "Locked")
        }
        .padding(16)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }

    private var statsCard: some View {
        VStack(spacing: 12) {
            statsRow(icon: "gamecontroller.fill", label: "Games Played",
                     value: "\(controller.store.gamesPlayed)",
                     tint: AtlasTheme.blue)
            statsRow(icon: "hexagon.fill", label: "Exact Tile Hits",
                     value: "\(controller.store.exactTileHits)",
                     tint: AtlasTheme.teal)
        }
        .padding(16)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }

    private func statsRow(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: Circle())
            Text(label)
                .font(.subheadline.weight(.medium))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gameCenterSection: some View {
        if controller.gameCenterManager.isAuthenticated {
            Button {
                controller.gameCenterManager.showLeaderboard()
            } label: {
                HStack {
                    Image(systemName: "trophy.fill")
                    Text("Leaderboard")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(GlassButtonStyle(shape: .capsule))
        } else {
            Button {
                controller.gameCenterManager.authenticate()
            } label: {
                HStack {
                    Image(systemName: "person.badge.plus")
                    Text("Sign in to Game Center")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
            }
            .buttonStyle(GlassButtonStyle(shape: .capsule))
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(.headline)
            ForEach(controller.store.gameHistory.suffix(5).reversed()) { game in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(game.totalScore) pts")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                            Text(game.mode.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(game.completedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ForEach(game.rounds) { round in
                        RoundScoreDot(score: round.score)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }

}
