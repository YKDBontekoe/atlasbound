import Foundation
import CoreLocation

/// Orchestrates GeoGuessr game state: rounds, scoring, persistence, and Game Center submission.
/// Views observe this; it owns no UI.
@MainActor
final class GeoGuessrController: ObservableObject {

    enum GamePhase: Equatable {
        case lobby
        case playing
        case roundResult
        case gameOver

        static func == (lhs: GamePhase, rhs: GamePhase) -> Bool {
            switch (lhs, rhs) {
            case (.lobby, .lobby), (.playing, .playing),
                 (.roundResult, .roundResult), (.gameOver, .gameOver):
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: GamePhase = .lobby
    @Published private(set) var targets: [CLLocationCoordinate2D] = []
    @Published private(set) var roundResults: [GeoGuessrRound] = []
    @Published private(set) var currentRound = 0
    @Published private(set) var lastRoundResult: GeoGuessrRound?
    @Published private(set) var lastGameResult: GeoGuessrGame?

    let store: GeoGuessrStore
    let gameCenterManager: GameCenterManager

    var runningScore: Int {
        roundResults.reduce(0) { $0 + $1.score }
    }

    init(store: GeoGuessrStore, gameCenterManager: GameCenterManager) {
        self.store = store
        self.gameCenterManager = gameCenterManager
    }

    func startNewGame() {
        targets = LookAroundLocationPool.generateTargets()
        roundResults = []
        currentRound = 0
        lastRoundResult = nil
        lastGameResult = nil
        phase = .playing
    }

    func submitGuess(_ guess: CLLocationCoordinate2D) {
        guard currentRound < targets.count else { return }
        let result = GeoGuessrRound(
            target: targets[currentRound],
            guess: guess,
            roundIndex: currentRound
        )
        roundResults.append(result)
        lastRoundResult = result
        phase = .roundResult
    }

    func advanceRound() {
        currentRound += 1
        if currentRound >= GeoGuessrConstants.roundsPerGame {
            let game = GeoGuessrGame(rounds: roundResults)
            store.record(game)
            lastGameResult = game
            if gameCenterManager.isAuthenticated {
                Task {
                    await gameCenterManager.submitScore(game.totalScore)
                }
            }
            phase = .gameOver
        } else {
            phase = .playing
        }
    }

    func returnToLobby() {
        phase = .lobby
    }
}
