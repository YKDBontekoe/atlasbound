import Foundation

/// Persists Pinpoint game history and high scores in SQLite.
@MainActor
final class PinpointStore: ObservableObject {
    @Published private(set) var gameHistory: [PinpointGame] = []
    @Published private(set) var highScoreWorldwide: Int = 0
    @Published private(set) var highScoreHomeTurf: Int = 0
    @Published private(set) var gamesPlayed: Int = 0
    @Published private(set) var exactTileHits: Int = 0

    private let database: AtlasDatabase
    private static let maxRetainedGames = 100

    init(fileURL: URL? = nil, database: AtlasDatabase? = nil) {
        if let database {
            self.database = database
        } else if let fileURL {
            self.database = AtlasDatabase.makeIsolated(fileURL: Self.sqliteURL(from: fileURL))
        } else {
            self.database = .shared
        }
        loadFromDisk()
    }

    private static func sqliteURL(from fileURL: URL) -> URL {
        fileURL.pathExtension.lowercased() == "json"
            ? fileURL.deletingPathExtension().appendingPathExtension("sqlite")
            : fileURL
    }

    func highScore(for mode: PinpointGameMode) -> Int {
        switch mode {
        case .worldwide: highScoreWorldwide
        case .homeTurf: highScoreHomeTurf
        }
    }

    func replaceCloudState(_ save: LegacyPinpointSave) {
        gameHistory = Array(save.games.suffix(Self.maxRetainedGames))
        gamesPlayed = max(save.gamesPlayed ?? 0, gameHistory.count)
        highScoreWorldwide = max(0, save.highScoreWorldwide)
        highScoreHomeTurf = max(0, save.highScoreHomeTurf)
        exactTileHits = max(0, save.exactTileHits)
        persistToDisk()
    }

    func clearCloudState() {
        replaceCloudState(LegacyPinpointSave(
            version: JSONFileStore.currentSchemaVersion,
            games: [],
            highScoreWorldwide: 0,
            highScoreHomeTurf: 0,
            exactTileHits: 0,
            gamesPlayed: 0
        ))
    }

    func resetLocalSession() {
        gameHistory = []
        highScoreWorldwide = 0
        highScoreHomeTurf = 0
        gamesPlayed = 0
        exactTileHits = 0
    }

    func record(_ game: PinpointGame) {
        gameHistory.append(game)
        if gameHistory.count > Self.maxRetainedGames {
            gameHistory.removeFirst(gameHistory.count - Self.maxRetainedGames)
        }
        gamesPlayed += 1
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

    private func loadFromDisk() {
        let loaded = database.loadPinpoint()
        gameHistory = Array(loaded.games.suffix(Self.maxRetainedGames))
        gamesPlayed = max(loaded.gamesPlayed, gameHistory.count)
        highScoreWorldwide = max(0, loaded.highScoreWorldwide)
        highScoreHomeTurf = max(0, loaded.highScoreHomeTurf)
        exactTileHits = max(0, loaded.exactTileHits)
    }

    private func persistToDisk() {
        database.replacePinpoint(
            games: gameHistory,
            highScoreWorldwide: highScoreWorldwide,
            highScoreHomeTurf: highScoreHomeTurf,
            gamesPlayed: gamesPlayed,
            exactTileHits: exactTileHits
        )
    }
}
