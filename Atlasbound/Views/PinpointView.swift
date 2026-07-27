import SwiftUI
import MapKit

/// Thin coordinator view — routes to the correct sub-screen based on controller phase.
struct PinpointView: View {
    @ObservedObject var controller: PinpointController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                phaseContent
                    .id(phaseIdentity)
                    .transition(phaseTransition)
            }
            .animation(AtlasMotion.optional(AtlasMotion.chrome, reduceMotion: reduceMotion), value: phaseIdentity)
            .navigationTitle("Pinpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(controller.isGameInProgress ? .hidden : .visible, for: .navigationBar)
            .toolbar(controller.isGameInProgress ? .hidden : .visible, for: .tabBar)
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .lobby:
            PinpointLobbyView(controller: controller)

        case .preparing:
            PinpointPreparingView(controller: controller)

        case .playing:
            if controller.currentRound < controller.targets.count {
                LookAroundGuessView(
                    target: controller.targets[controller.currentRound],
                    mode: controller.currentMode,
                    roundIndex: controller.currentRound,
                    totalRounds: PinpointConstants.roundsPerGame,
                    currentScore: controller.runningScore,
                    roundSeconds: PinpointConstants.roundSeconds(for: controller.currentMode),
                    regionConstraint: controller.atlasRegionConstraint,
                    onGuess: { controller.submitGuess($0) },
                    onQuit: { controller.returnToLobby() }
                )
            }

        case .roundResult:
            if let result = controller.lastRoundResult {
                PinpointRoundResultView(
                    result: result,
                    roundNumber: controller.currentRound,
                    totalRounds: PinpointConstants.roundsPerGame,
                    runningTotal: controller.runningScore,
                    onNext: { controller.advanceRound() }
                )
            }

        case .gameOver:
            if let game = controller.lastGameResult {
                PinpointGameOverView(game: game, controller: controller)
            }
        }
    }

    private var phaseIdentity: String {
        switch controller.phase {
        case .lobby: "lobby"
        case .preparing: "preparing"
        case .playing: "playing-\(controller.currentRound)"
        case .roundResult: "result-\(controller.currentRound)"
        case .gameOver: "gameOver"
        }
    }

    private var phaseTransition: AnyTransition {
        .opacity.combined(with: .offset(y: reduceMotion ? 0 : 12))
    }
}

/// Small reusable score indicator dot.
struct RoundScoreDot: View {
    let score: Int

    var body: some View {
        Circle()
            .fill(PinpointScoreStyle.color(for: score))
            .frame(width: 8, height: 8)
    }
}
