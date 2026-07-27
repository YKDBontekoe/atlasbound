import SwiftUI
import MapKit

/// Thin coordinator view — routes to the correct sub-screen based on controller phase.
struct GeoGuessrView: View {
    @ObservedObject var controller: GeoGuessrController

    var body: some View {
        NavigationStack {
            ZStack {
                switch controller.phase {
                case .lobby:
                    GeoGuessrLobbyView(controller: controller)

                case .playing:
                    if controller.currentRound < controller.targets.count {
                        LookAroundGuessView(
                            target: controller.targets[controller.currentRound],
                            roundIndex: controller.currentRound,
                            totalRounds: GeoGuessrConstants.roundsPerGame,
                            currentScore: controller.runningScore,
                            onGuess: { controller.submitGuess($0) }
                        )
                        .id("round-\(controller.currentRound)")
                    }

                case .roundResult:
                    if let result = controller.lastRoundResult {
                        GeoGuessrRoundResultView(
                            result: result,
                            roundNumber: controller.currentRound,
                            totalRounds: GeoGuessrConstants.roundsPerGame,
                            runningTotal: controller.runningScore,
                            onNext: { controller.advanceRound() }
                        )
                    }

                case .gameOver:
                    if let game = controller.lastGameResult {
                        GeoGuessrGameOverView(game: game, controller: controller)
                    }
                }
            }
            .navigationTitle("GeoGuessr")
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
