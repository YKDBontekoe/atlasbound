import XCTest
import CoreLocation
@testable import Atlasbound

final class SharedTreasureModelsTests: XCTestCase {
    func testSpawnRequestUsesServerWireKeys() throws {
        let request = SharedTreasureSpawnRequest(
            tileID: "hex:20:1:2",
            latitude: 51.8,
            longitude: 4.6,
            isVault: false,
            dayKey: "2026-08-09"
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(object?["tile_id"] as? String, "hex:20:1:2")
        XCTAssertEqual(object?["is_vault"] as? Bool, false)
        XCTAssertEqual(object?["day_key"] as? String, "2026-08-09")
    }

    func testEventIsActiveOnlyBeforeExpiryAndBeforeClaim() {
        let event = SharedTreasureEvent(
            id: UUID(),
            tileID: "hex:20:1:2",
            latitude: 51.8,
            longitude: 4.6,
            name: "Park",
            category: "Park",
            clue: "A mark waits nearby.",
            distanceMeters: 400,
            isVault: false,
            createdAt: .now.addingTimeInterval(-10),
            expiresAt: .now.addingTimeInterval(60),
            claimedAt: nil
        )
        XCTAssertTrue(event.isActive)
        XCTAssertEqual(event.coordinate.latitude, 51.8, accuracy: 0.0001)
    }
}
