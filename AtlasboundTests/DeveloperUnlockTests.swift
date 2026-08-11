import XCTest
@testable import Atlasbound

#if DEBUG
@MainActor
final class DeveloperUnlockTests: XCTestCase {
    func testAtlasUnlockSeedsCanonicalLegendaryTilesAndXP() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("developer-atlas-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TileStore(fileURL: url, installationID: "developer-test")
        store.debugUnlockAtlas(around: TileCoordinate(q: 10, r: -4), radius: 2, date: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(store.discoveredTileCount, 19)
        XCTAssertTrue(store.discoveredTiles.allSatisfy { $0.state == .legendary && $0.id.hasPrefix("hex:20:") })
        XCTAssertGreaterThanOrEqual(store.discoveryXPTotal, 1_900)
    }

    func testCardUnlockMakesEveryCatalogBlueprintAvailable() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("developer-cards-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CardStore(fileURL: url, now: Date(timeIntervalSince1970: 1))
        store.debugUnlockAll(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.blueprints.count, CrewfrontCatalog.blueprints.count)
        XCTAssertTrue(CrewfrontCatalog.blueprints.allSatisfy { store.quantity(of: $0.id) >= 2 })
    }
}
#endif
