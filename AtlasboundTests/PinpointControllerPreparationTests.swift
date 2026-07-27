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
        XCTAssertEqual(controller.preparationTargetCount, PinpointConstants.roundsPerGame)
        XCTAssertEqual(controller.currentMode, .worldwide)

        controller.cancelPreparation()
        XCTAssertEqual(controller.phase, .lobby)
        XCTAssertEqual(controller.preparationFoundCount, 0)
    }
}
