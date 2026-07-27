import SwiftUI

/// Lobby screen: stats, start game, Game Center sign-in, recent games.
struct GeoGuessrLobbyView: View {
    @ObservedObject var controller: GeoGuessrController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                statsCard
                startButton
                gameCenterSection

                if let error = controller.gameCenterManager.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(AtlasTheme.finishRed)
                }

                if !controller.store.gameHistory.isEmpty {
                    recentGamesSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var heroSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AtlasTheme.blue, AtlasTheme.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("GeoGuessr")
                .font(.largeTitle.bold())
            Text("Guess your location from Look Around")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 40)
    }

    private var statsCard: some View {
        VStack(spacing: 12) {
            statsRow(icon: "star.fill", label: "High Score",
                     value: "\(controller.store.highScore) / \(GeoGuessrConstants.maxPossibleScore)",
                     tint: AtlasTheme.gold)
            statsRow(icon: "gamecontroller.fill", label: "Games Played",
                     value: "\(controller.store.gamesPlayed)",
                     tint: AtlasTheme.blue)
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

    private var startButton: some View {
        Button {
            controller.startNewGame()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start Game")
                    .font(.headline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
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
                        Text("\(game.totalScore) pts")
                            .font(.subheadline.weight(.bold).monospacedDigit())
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
