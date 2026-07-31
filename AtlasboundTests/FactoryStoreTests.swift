import XCTest
@testable import Atlasbound

@MainActor
final class FactoryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-factory-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: fileURL.path + "-shm"))
        fileURL = nil
        super.tearDown()
    }

    func testFactoryRoundTripContainsIDsButNoGeometry() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let store = FactoryStore(fileURL: fileURL, now: start)
        let tileID = TileEngine.makeTileID(q: 4, r: -2, sizeMeters: 20)
        let structure = PlacedFactoryStructure(
            tileID: tileID,
            definitionID: "trailhead_depot",
            tier: 1,
            inputBuffer: [:],
            outputBuffer: ["cobble_chip": 12],
            selectedRecipeID: nil,
            recipeProgressMinutes: 0,
            extractedUnits: 0,
            priority: .high,
            fueledMinutes: 0,
            placedAt: start
        )
        store.update {
            $0.structures[tileID] = structure
            $0.unlockedResearchIDs.insert("logistics_1")
        }

        let reloaded = FactoryStore(fileURL: fileURL, now: start)
        XCTAssertEqual(reloaded.structures[tileID], structure)
        XCTAssertTrue(reloaded.unlockedResearchIDs.contains("logistics_1"))

        let encoded = try JSONEncoder().encode(structure)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertTrue(json.contains(tileID))
        XCTAssertFalse(json.contains("latitude"))
        XCTAssertFalse(json.contains("longitude"))
        XCTAssertFalse(json.contains("polygon"))
        XCTAssertFalse(json.contains("networkID"))
    }

    func testMissingFactoryStateStartsEmpty() throws {
        let store = FactoryStore(fileURL: fileURL, now: Date(timeIntervalSince1970: 2_000))
        XCTAssertTrue(store.structures.isEmpty)
        XCTAssertEqual(store.unlockedResearchIDs, ["foundations"])
    }

    func testClearResetsFactoryResearchAndProduction() {
        let store = FactoryStore(fileURL: fileURL)
        store.update {
            $0.unlockedResearchIDs.insert("mechanics")
            $0.lifetimeProduced["stone_block"] = 25
        }
        store.clear()
        XCTAssertEqual(store.unlockedResearchIDs, ["foundations"])
        XCTAssertTrue(store.lifetimeProduced.isEmpty)
        XCTAssertTrue(store.structures.isEmpty)
    }

    func testReloadDropsNonCanonicalAndUnknownStructures() {
        let store = FactoryStore(fileURL: fileURL)
        let invalid = PlacedFactoryStructure(
            tileID: "not-a-canonical-tile",
            definitionID: "unknown_factory",
            tier: 99,
            inputBuffer: ["unknown_item": -4],
            outputBuffer: [:],
            selectedRecipeID: "unknown_recipe",
            recipeProgressMinutes: -1,
            extractedUnits: -2,
            priority: .normal,
            fueledMinutes: -3,
            placedAt: .now
        )
        store.update {
            $0.structures[invalid.tileID] = invalid
            $0.unlockedResearchIDs.insert("unknown_research")
            $0.lifetimeProduced["unknown_item"] = 20
        }

        let reloaded = FactoryStore(fileURL: fileURL)
        XCTAssertTrue(reloaded.structures.isEmpty)
        XCTAssertEqual(reloaded.unlockedResearchIDs, ["foundations"])
        XCTAssertTrue(reloaded.lifetimeProduced.isEmpty)
    }
}
