import Foundation

/// Persists Pinpoint game history and high scores as JSON.
/// Single responsibility: persistence only — no game logic.
@MainActor
final class PinpointStore: ObservableObject {
    @Published private(set) var gameHistory: [PinpointGame] = []
    @Published private(set) var highScoreWorldwide: Int = 0
    @Published private(set) var highScoreHomeTurf: Int = 0
    @Published private(set) var gamesPlayed: Int = 0
    @Published private(set) var exactTileHits: Int = 0

    private let fileURL: URL

    private static let fileName = "atlasbound-pinpoint.json"

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? JSONFileStore.documentsURL(fileName: Self.fileName)
        loadFromDisk()
    }

    func highScore(for mode: PinpointGameMode) -> Int {
        switch mode {
        case .worldwide: highScoreWorldwide
        case .homeTurf: highScoreHomeTurf
        }
    }

    func record(_ game: PinpointGame) {
        gameHistory.append(game)
        gamesPlayed = gameHistory.count
        exactTileHits += game.rounds.filter(\.hitExactTile).count

        switch game.mode {
        case .worldwide:
            if game.totalScore > highScoreWorldwide {
                highScoreWorldwide = game.totalScore
            }
        case .homeTurf:
            if game.totalScore > highScoreHomeTurf {
                highScoreHomeTurf = game.totalScore
            }
        }
        persistToDisk()
    }

    func clearHistory() {
        gameHistory = []
        highScoreWorldwide = 0
        highScoreHomeTurf = 0
        gamesPlayed = 0
        exactTileHits = 0
        persistToDisk()
    }

    // MARK: - Disk

    private struct SaveFile: Codable {
        let games: [PinpointGame]
        let highScoreWorldwide: Int
        let highScoreHomeTurf: Int
        let exactTileHits: Int
    }

    private func loadFromDisk() {
        guard let save = JSONFileStore.load(SaveFile.self, from: fileURL) else {
            gameHistory = []
            return
        }
        gameHistory = save.games
        gamesPlayed = save.games.count
        highScoreWorldwide = save.highScoreWorldwide
        highScoreHomeTurf = save.highScoreHomeTurf
        exactTileHits = save.exactTileHits
    }

    private func persistToDisk() {
        let save = SaveFile(
            games: gameHistory,
            highScoreWorldwide: highScoreWorldwide,
            highScoreHomeTurf: highScoreHomeTurf,
            exactTileHits: exactTileHits
        )
        JSONFileStore.save(save, to: fileURL)
    }
}
