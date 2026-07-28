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
    @Published private(set) var preparationFoundCount = 0
    @Published private(set) var preparationTargetCount = PinpointConstants.roundsPerGame

    let store: PinpointStore
    let tileStore: TileStore
    let gameCenterManager: GameCenterManager
    private var preparationTask: Task<Void, Never>?
    private var preparationID: UUID?

    var runningScore: Int {
        roundResults.reduce(0) { $0 + $1.score }
    }

    /// Active Pinpoint uses a focused, full-screen presentation.
    var isGameInProgress: Bool {
        phase == .preparing || phase == .playing || phase == .roundResult
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

        preparationTask?.cancel()
        let preparationID = UUID()
        self.preparationID = preparationID
        phase = .preparing
        preparationError = nil
        currentMode = mode
        unlockedAreaM2AtGameStart = unlockedAreaM2
        sessionFamiliarityXP = 0
        preparationFoundCount = 0
        preparationTargetCount = mode == .worldwide ? 1 : PinpointConstants.roundsPerGame
        atlasRegionConstraint = mode == .homeTurf
            ? LookAroundLocationPool.atlasRegion(for: tileStore.discoveredTiles, engine: tileStore.tileEngine)
            : nil

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newTargets = try await self.prepareTargets(mode: mode, preparationID: preparationID)

                try Task.checkCancellation()
                guard self.preparationID == preparationID else { return }

                targets = newTargets
                roundResults = []
                currentRound = 0
                lastRoundResult = nil
                lastGameResult = nil
                phase = .playing
            } catch {
                guard !Task.isCancelled else { return }
                guard self.preparationID == preparationID else { return }
                preparationError = error.localizedDescription
                preparationFoundCount = 0
                phase = .lobby
            }
            if self.preparationID == preparationID {
                preparationTask = nil
                self.preparationID = nil
            }
        }
    }

    /// Returns immediately to the lobby so a slow Maps request never traps the player.
    func cancelPreparation() {
        guard phase == .preparing else { return }
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = nil
        preparationFoundCount = 0
        phase = .lobby
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
        } else if currentRound < targets.count {
            phase = .playing
        } else {
            prepareNextWorldwideRound()
        }
    }

    func returnToLobby() {
        phase = .lobby
        preparationError = nil
        preparationFoundCount = 0
    }

    // MARK: - Preparation

    private func prepareTargets(mode: PinpointGameMode, preparationID: UUID) async throws -> [CLLocationCoordinate2D] {
        try Task.checkCancellation()
        guard self.preparationID == preparationID else { throw CancellationError() }

        switch mode {
        case .worldwide:
            let target = try await generateWorldwideTargetWithBackoff(excluding: [])
            preparationFoundCount = 1
            return [target]

        case .homeTurf:
            let tiles = tileStore.discoveredTiles
            let targets = try LookAroundLocationPool.immediateHomeTurfTargets(
                discoveredTiles: tiles,
                engine: tileStore.tileEngine,
                count: PinpointConstants.roundsPerGame
            )
            preparationFoundCount = targets.count
            return targets
        }
    }

    private func prepareNextWorldwideRound() {
        guard currentMode == .worldwide else {
            phase = .playing
            return
        }

        preparationTask?.cancel()
        let preparationID = UUID()
        self.preparationID = preparationID
        preparationFoundCount = 0
        preparationTargetCount = 1
        preparationError = nil
        phase = .preparing

        preparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let target = try await generateWorldwideTargetWithBackoff(
                    excluding: targets
                )
                try Task.checkCancellation()
                guard self.preparationID == preparationID else { return }
                targets.append(target)
                preparationFoundCount = 1
                phase = .playing
            } catch {
                guard !Task.isCancelled, self.preparationID == preparationID else { return }
                preparationError = error.localizedDescription
                preparationFoundCount = 0
                phase = .lobby
            }

            if self.preparationID == preparationID {
                preparationTask = nil
                self.preparationID = nil
            }
        }
    }

    private func generateWorldwideTargetWithBackoff(
        excluding existing: [CLLocationCoordinate2D]
    ) async throws -> CLLocationCoordinate2D {
        let retryDelays = [1, 2, 3]

        for attempt in 0...retryDelays.count {
            try Task.checkCancellation()
            do {
                return try await LookAroundLocationPool.generateWorldwideTarget(
                    excluding: existing
                )
            } catch let error as LookAroundLocationPool.GenerationError {
                guard attempt < retryDelays.count else { throw error }
                try await Task.sleep(for: .seconds(retryDelays[attempt]))
            }
        }

        throw LookAroundLocationPool.GenerationError.worldwideGenerationFailed
    }
}
