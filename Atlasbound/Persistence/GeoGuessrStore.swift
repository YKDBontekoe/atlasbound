import Foundation

/// Persists GeoGuessr game history and high scores as JSON.
@MainActor
final class GeoGuessrStore: ObservableObject {
    @Published private(set) var gameHistory: [GeoGuessrEngine.GameResult] = []
    @Published private(set) var highScore: Int = 0
    @Published private(set) var gamesPlayed: Int = 0

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

    private static let fileName = "atlasbound-geoguessr.json"

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

    func record(_ game: GeoGuessrEngine.GameResult) {
        gameHistory.append(game)
        gamesPlayed = gameHistory.count
        if game.totalScore > highScore {
            highScore = game.totalScore
        }
        persistToDisk()
    }

    func clearHistory() {
        gameHistory = []
        highScore = 0
        gamesPlayed = 0
        persistToDisk()
    }

    // MARK: - Disk

    private struct SaveFile: Codable {
        let games: [GeoGuessrEngine.GameResult]
        let highScore: Int
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let save = try decoder.decode(SaveFile.self, from: data)
            gameHistory = save.games
            gamesPlayed = save.games.count
            highScore = save.highScore
        } catch {
            gameHistory = []
        }
    }

    private func persistToDisk() {
        let save = SaveFile(games: gameHistory, highScore: highScore)
        do {
            let data = try encoder.encode(save)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Keep in-memory state on write failure.
        }
    }
}
