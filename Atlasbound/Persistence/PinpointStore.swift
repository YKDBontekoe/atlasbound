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
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let fileName = "atlasbound-pinpoint.json"

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = docs.appendingPathComponent(Self.fileName)
        }
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let save = try decoder.decode(SaveFile.self, from: data)
            gameHistory = save.games
            gamesPlayed = save.games.count
            highScoreWorldwide = save.highScoreWorldwide
            highScoreHomeTurf = save.highScoreHomeTurf
            exactTileHits = save.exactTileHits
        } catch {
            gameHistory = []
        }
    }

    private func persistToDisk() {
        let save = SaveFile(
            games: gameHistory,
            highScoreWorldwide: highScoreWorldwide,
            highScoreHomeTurf: highScoreHomeTurf,
            exactTileHits: exactTileHits
        )
        do {
            let data = try encoder.encode(save)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep in-memory state on write failure.
        }
    }
}
