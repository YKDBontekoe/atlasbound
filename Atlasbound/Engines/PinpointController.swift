import Foundation
import CoreLocation
import MapKit

/// Orchestrates Pinpoint game state: rounds, scoring, persistence, and Game Center submission.
/// Views observe this; it owns no UI.
@MainActor
final class PinpointController: ObservableObject {

    enum GamePhase: Equatable {
        case lobby
        case preparing
        case playing
        case roundResult
        case gameOver

        static func == (lhs: GamePhase, rhs: GamePhase) -> Bool {
            switch (lhs, rhs) {
            case (.lobby, .lobby), (.preparing, .preparing), (.playing, .playing),
                 (.roundResult, .roundResult), (.gameOver, .gameOver):
                return true
            default:
                return false
            }
        }
    }

    @Published private(set) var phase: GamePhase = .lobby
    @Published private(set) var currentMode: PinpointGameMode = .worldwide
    @Published private(set) var targets: [CLLocationCoordinate2D] = []
    @Published private(set) var roundResults: [PinpointRound] = []
    @Published private(set) var currentRound = 0
    @Published private(set) var lastRoundResult: PinpointRound?
    @Published private(set) var lastGameResult: PinpointGame?
    @Published private(set) var unlockedAreaM2AtGameStart: Double = 0
    @Published private(set) var atlasRegionConstraint: MKCoordinateRegion?
    @Published var preparationError: String?
    @Published private(set) var sessionFamiliarityXP: Int = 0

    let store: PinpointStore
    let tileStore: TileStore
    let gameCenterManager: GameCenterManager

    var runningScore: Int {
        roundResults.reduce(0) { $0 + $1.score }
    }

    var unlockedAreaM2: Double {
        PinpointScoring.unlockedAreaM2(
            discoveredCount: tileStore.discoveredTiles.count,
            tileSizeMeters: tileStore.tileEngine.tileSizeMeters
        )
    }

    var homeTurfUnlocked: Bool {
        tileStore.discoveredTiles.count >= PinpointConstants.homeTurfMinTiles
    }

    var homeTurfTilesNeeded: Int {
        max(0, PinpointConstants.homeTurfMinTiles - tileStore.discoveredTiles.count)
    }

    init(store: PinpointStore, tileStore: TileStore, gameCenterManager: GameCenterManager) {
        self.store = store
        self.tileStore = tileStore
        self.gameCenterManager = gameCenterManager
    }

    func startNewGame(mode: PinpointGameMode) {
        guard mode != .homeTurf || homeTurfUnlocked else { return }

        phase = .preparing
        preparationError = nil
        currentMode = mode
        unlockedAreaM2AtGameStart = unlockedAreaM2
        sessionFamiliarityXP = 0
        atlasRegionConstraint = mode == .homeTurf
            ? LookAroundLocationPool.atlasRegion(for: tileStore.discoveredTiles, engine: tileStore.tileEngine)
            : nil

        Task {
            do {
                let newTargets: [CLLocationCoordinate2D]
                switch mode {
                case .worldwide:
                    newTargets = try await LookAroundLocationPool.generateWorldwideTargets()
                case .homeTurf:
                    newTargets = try await LookAroundLocationPool.generateHomeTurfTargets(
                        discoveredTiles: tileStore.discoveredTiles,
                        engine: tileStore.tileEngine
                    )
                }

                targets = newTargets
                roundResults = []
                currentRound = 0
                lastRoundResult = nil
                lastGameResult = nil
                phase = .playing
            } catch {
                preparationError = error.localizedDescription
                phase = .lobby
            }
        }
    }

    func submitGuess(_ guess: CLLocationCoordinate2D) {
        guard currentRound < targets.count else { return }

        let target = targets[currentRound]
        let engine = tileStore.tileEngine
        let guessTileID = engine.tileID(for: guess)
        let guessInAtlas = tileStore.tiles[guessTileID]?.isDiscovered ?? false

        let result = PinpointRound(
            mode: currentMode,
            target: target,
            guess: guess,
            roundIndex: currentRound,
            tileEngine: engine,
            guessInDiscoveredAtlas: guessInAtlas,
            unlockedAreaM2: unlockedAreaM2AtGameStart
        )

        if result.familiarityXPAwarded > 0 {
            tileStore.addXP(discovery: 0, familiarity: result.familiarityXPAwarded)
            sessionFamiliarityXP += result.familiarityXPAwarded
        }

        roundResults.append(result)
        lastRoundResult = result
        phase = .roundResult
    }

    func advanceRound() {
        currentRound += 1
        if currentRound >= PinpointConstants.roundsPerGame {
            let game = PinpointGame(
                mode: currentMode,
                rounds: roundResults,
                unlockedAreaM2AtGameStart: unlockedAreaM2AtGameStart
            )
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
        preparationError = nil
    }
}

import MapKit
