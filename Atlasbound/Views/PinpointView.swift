import SwiftUI
import MapKit

/// Thin coordinator view — routes to the correct sub-screen based on controller phase.
struct PinpointView: View {
    @ObservedObject var controller: PinpointController

    var body: some View {
        NavigationStack {
            ZStack {
                switch controller.phase {
                case .lobby, .preparing:
                    PinpointLobbyView(controller: controller)

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
                            onGuess: { controller.submitGuess($0) }
                        )
                        .id("round-\(controller.currentRound)-\(controller.currentMode.rawValue)")
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
            .navigationTitle("Pinpoint")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// Small reusable score indicator dot.
struct RoundScoreDot: View {
    let score: Int

    private var color: Color {
        if score >= 4500 { return AtlasTheme.gold }
        if score >= 3000 { return AtlasTheme.teal }
        if score >= 1000 { return AtlasTheme.blue }
        return AtlasTheme.finishRed
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
