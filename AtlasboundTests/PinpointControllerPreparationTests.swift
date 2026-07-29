import XCTest
import CoreLocation
@testable import Atlasbound

@MainActor
final class PinpointControllerPreparationTests: XCTestCase {

    func testPreparationProgressDefaultsAndResetsOnReturnToLobby() {
        let tileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpoint-prep-tiles-\(UUID().uuidString).json")
        let pinpointURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpoint-prep-history-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tileURL)
            try? FileManager.default.removeItem(at: pinpointURL)
        }

        let controller = PinpointController(
            store: PinpointStore(fileURL: pinpointURL),
            tileStore: TileStore(fileURL: tileURL, installationID: "prep-test"),
            gameCenterManager: GameCenterManager()
        )

        XCTAssertEqual(controller.preparationFoundCount, 0)
        XCTAssertEqual(controller.preparationTargetCount, PinpointConstants.roundsPerGame)
        XCTAssertEqual(controller.phase, .lobby)

        controller.startNewGame(mode: .worldwide)
        XCTAssertEqual(controller.phase, .preparing)
        XCTAssertEqual(controller.preparationFoundCount, 0)
        XCTAssertEqual(controller.preparationTargetCount, 1)
        XCTAssertEqual(controller.currentMode, .worldwide)

        controller.cancelPreparation()
        XCTAssertEqual(controller.phase, .lobby)
        XCTAssertEqual(controller.preparationFoundCount, 0)
    }

    func testStoreBoundsHistoryWithoutLosingLifetimeCount() {
        let pinpointURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpoint-bounded-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: pinpointURL) }
        let store = PinpointStore(fileURL: pinpointURL)

        for index in 0..<101 {
            store.record(
                PinpointGame(
                    mode: .worldwide,
                    rounds: [],
                    unlockedAreaM2AtGameStart: 0,
                    completedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }

        XCTAssertEqual(store.gameHistory.count, 100)
        XCTAssertEqual(store.gamesPlayed, 101)

        let reloaded = PinpointStore(fileURL: pinpointURL)
        XCTAssertEqual(reloaded.gameHistory.count, 100)
        XCTAssertEqual(reloaded.gamesPlayed, 101)
        XCTAssertEqual(reloaded.gameHistory.first?.completedAt, Date(timeIntervalSince1970: 1))
    }

    func testInvalidStateTransitionsAreIgnored() {
        let tileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpoint-state-tiles-\(UUID().uuidString).json")
        let pinpointURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpoint-state-history-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tileURL)
            try? FileManager.default.removeItem(at: pinpointURL)
        }
        let controller = PinpointController(
            store: PinpointStore(fileURL: pinpointURL),
            tileStore: TileStore(fileURL: tileURL, installationID: "state-test"),
            gameCenterManager: GameCenterManager()
        )

        controller.submitGuess(CLLocationCoordinate2D(latitude: 0, longitude: 0))
        controller.advanceRound()

        XCTAssertEqual(controller.phase, .lobby)
        XCTAssertEqual(controller.currentRound, 0)
        XCTAssertTrue(controller.roundResults.isEmpty)
    }
}
