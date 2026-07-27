import SwiftUI

/// End-of-game screen: total score, per-round breakdown, leaderboard, play again.
struct PinpointGameOverView: View {
    let game: PinpointGame
    @ObservedObject var controller: PinpointController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedScore = 0
    @State private var showBreakdown = false

    private var isNewHighScore: Bool {
        game.totalScore >= controller.store.highScore(for: game.mode)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(game.mode.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if isNewHighScore {
                        CelebrateBadge {
                            Text("New High Score!")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(AtlasTheme.gold)
                        }
                    }
                    Text("\(displayedScore)")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .animation(AtlasMotion.number, value: displayedScore)
                    Text("out of \(PinpointConstants.maxPossibleScore)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if game.totalFamiliarityXPAwarded > 0 {
                        CelebrateBadge {
                            Text("+\(game.totalFamiliarityXPAwarded) familiarity XP earned")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AtlasTheme.gold)
                        }
                    }
                }
                .padding(.top, 32)
                .staggeredAppear(index: 0)

                roundBreakdown
                    .opacity(showBreakdown || reduceMotion ? 1 : 0)
                    .offset(y: showBreakdown || reduceMotion ? 0 : 12)
                actionButtons
                    .staggeredAppear(index: 2)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .onAppear {
            AtlasHaptics.success()
            if reduceMotion {
                displayedScore = game.totalScore
                showBreakdown = true
                return
            }
            withAnimation(AtlasMotion.celebrate) {
                displayedScore = game.totalScore
            }
            withAnimation(AtlasMotion.chrome.delay(0.15)) {
                showBreakdown = true
            }
        }
    }

    private var roundBreakdown: some View {
        VStack(spacing: 8) {
            ForEach(game.rounds) { round in
                HStack {
                    Text("Round \(round.roundIndex + 1)")
                        .font(.subheadline)
                    if round.hitExactTile {
                        Image(systemName: "hexagon.fill")
                            .font(.caption2)
                            .foregroundStyle(AtlasTheme.gold)
                    }
                    Spacer()
                    Text(PinpointScoring.formatDistance(round.distanceMeters))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(round.score) pts")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 6)
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

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                controller.startNewGame(mode: game.mode)
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Play Again")
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))

            if controller.gameCenterManager.isAuthenticated {
                Button {
                    controller.gameCenterManager.showLeaderboard()
                } label: {
                    HStack {
                        Image(systemName: "trophy.fill")
                        Text("Leaderboard")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                }
                .buttonStyle(GlassButtonStyle(shape: .capsule))
            }

            Button {
                controller.returnToLobby()
            } label: {
                Text("Back to Menu")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
