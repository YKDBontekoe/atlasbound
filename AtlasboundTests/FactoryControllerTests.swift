import XCTest
import CoreLocation
@testable import Atlasbound

@MainActor
final class FactoryControllerTests: XCTestCase {
    private var URLs: [URL] = []

    override func tearDown() {
        for url in URLs {
            try? FileManager.default.removeItem(at: url)
        }
        URLs = []
        super.tearDown()
    }

    func testNearbyPlacementConsumesKitAndPersistsStructure() {
        let now = Date(timeIntervalSince1970: 50_000)
        let context = makeContext(now: now)
        let coordinate = TileCoordinate(q: 10, r: -4)
        let tileID = TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: 20)
        context.tileStore.upsert(
            WorldTile(
                id: tileID,
                coordinate: coordinate,
                state: .explored,
                masteryXP: 150,
                visitCount: 2
            )
        )
        grant("trail_road_kit", quantity: 1, to: context.inventory)
        context.controller.updatePlayerLocation(
            location(at: context.tileStore.tileEngine.centerCoordinate(for: coordinate), timestamp: now)
        )
        context.controller.selectBuildDefinition("trail_road")

        XCTAssertTrue(context.controller.validation(for: tileID, now: now).isAllowed)
        XCTAssertTrue(context.controller.placeSelected(at: tileID, now: now))
        XCTAssertEqual(context.inventory.quantity(of: "trail_road_kit"), 0)
        XCTAssertEqual(context.factoryStore.structures[tileID]?.definitionID, "trail_road")

        let reloaded = FactoryStore(fileURL: context.factoryURL, now: now)
        XCTAssertEqual(reloaded.structures[tileID]?.definitionID, "trail_road")
    }

    func testResearchConsumesInsightsAndHonorsExplorerGate() {
        let context = makeContext()
        grant("atlas_insight", quantity: 10, to: context.inventory)
        XCTAssertFalse(context.controller.unlockResearch("logistics_1"))
        XCTAssertEqual(context.inventory.quantity(of: "atlas_insight"), 10)

        context.tileStore.addXP(discovery: 8_000, familiarity: 0)
        XCTAssertGreaterThanOrEqual(context.controller.explorerLevel, 5)
        XCTAssertTrue(context.controller.unlockResearch("logistics_1"))
        XCTAssertEqual(context.inventory.quantity(of: "atlas_insight"), 0)
        XCTAssertTrue(context.factoryStore.unlockedResearchIDs.contains("logistics_1"))
    }

    func testClearingFactoryDoesNotClearBackpack() {
        let context = makeContext()
        grant("trail_road_kit", quantity: 2, to: context.inventory)
        context.factoryStore.update { $0.unlockedResearchIDs.insert("mechanics") }
        context.controller.clearFactory()
        XCTAssertEqual(context.inventory.quantity(of: "trail_road_kit"), 2)
        XCTAssertEqual(context.factoryStore.unlockedResearchIDs, ["foundations"])
    }

    func testNearbyPlayerCanLoadAndUnloadGeneratorWithoutDepot() {
        let now = Date(timeIntervalSince1970: 60_000)
        let context = makeContext(now: now)
        let coordinate = TileCoordinate(q: 3, r: 2)
        let tileID = TileEngine.makeTileID(q: coordinate.q, r: coordinate.r, sizeMeters: 20)
        let generator = PlacedFactoryStructure(
            tileID: tileID,
            definitionID: "waystone_dynamo",
            tier: 1,
            inputBuffer: [:],
            outputBuffer: [:],
            selectedRecipeID: nil,
            recipeProgressMinutes: 0,
            extractedUnits: 0,
            priority: .normal,
            fueledMinutes: 0,
            placedAt: now
        )
        context.factoryStore.update { $0.structures[tileID] = generator }
        context.controller.updatePlayerLocation(
            location(at: context.tileStore.tileEngine.centerCoordinate(for: coordinate), timestamp: now)
        )
        grant("amber_resin", quantity: 2, to: context.inventory)

        XCTAssertTrue(
            context.controller.deposit(
                itemID: "amber_resin",
                quantity: 2,
                into: tileID,
                now: now
            )
        )
        XCTAssertEqual(context.inventory.quantity(of: "amber_resin"), 0)
        XCTAssertEqual(context.factoryStore.structures[tileID]?.inputBuffer["amber_resin"], 2)
        XCTAssertTrue(
            context.controller.withdraw(
                itemID: "amber_resin",
                quantity: 1,
                from: tileID,
                inputBuffer: true,
                now: now
            )
        )
        XCTAssertEqual(context.inventory.quantity(of: "amber_resin"), 1)
        XCTAssertEqual(context.factoryStore.structures[tileID]?.inputBuffer["amber_resin"], 1)
    }

    func testDisconnectedNetworkCannotBorrowRemotePower() {
        let context = makeContext()
        let roadA = factoryStructure(q: 0, r: 0, definitionID: "trail_road")
        var generator = factoryStructure(q: -1, r: 0, definitionID: "waystone_dynamo")
        generator.fueledMinutes = 5
        let roadB = factoryStructure(q: 20, r: 20, definitionID: "trail_road")
        var refinery = factoryStructure(q: 19, r: 20, definitionID: "atlas_refinery")
        refinery.selectedRecipeID = "refine_stone_block"
        context.factoryStore.update {
            $0.structures = Dictionary(
                uniqueKeysWithValues: [roadA, generator, roadB, refinery].map { ($0.tileID, $0) }
            )
        }

        XCTAssertEqual(context.controller.totalPowerSupply, 20)
        XCTAssertEqual(context.controller.totalPowerDemand, 4)
        XCTAssertEqual(context.controller.status(for: refinery), .noPower)
        XCTAssertEqual(context.controller.networkMetrics.count, 2)
    }

    private func makeContext(now: Date = Date(timeIntervalSince1970: 40_000)) -> (
        controller: FactoryController,
        tileStore: TileStore,
        inventory: InventoryStore,
        factoryStore: FactoryStore,
        factoryURL: URL
    ) {
        let worldURL = temporaryURL("world")
        let inventoryURL = temporaryURL("inventory")
        let factoryURL = temporaryURL("factory")
        let tileStore = TileStore(fileURL: worldURL, installationID: "factory-controller-tests")
        let inventory = InventoryStore(fileURL: inventoryURL)
        let factoryStore = FactoryStore(fileURL: factoryURL, now: now)
        let controller = FactoryController(
            store: factoryStore,
            tileStore: tileStore,
            inventoryStore: inventory
        )
        return (controller, tileStore, inventory, factoryStore, factoryURL)
    }

    private func grant(_ itemID: String, quantity: Int, to store: InventoryStore) {
        _ = store.collect(
            FieldFind(
                id: "find:test:\(UUID().uuidString)",
                tileID: "hex:20:0:0",
                dayKey: "test",
                itemID: itemID,
                quantity: quantity,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
    }

    private func factoryStructure(
        q: Int,
        r: Int,
        definitionID: String
    ) -> PlacedFactoryStructure {
        PlacedFactoryStructure(
            tileID: TileEngine.makeTileID(q: q, r: r, sizeMeters: 20),
            definitionID: definitionID,
            tier: 1,
            inputBuffer: [:],
            outputBuffer: [:],
            selectedRecipeID: nil,
            recipeProgressMinutes: 0,
            extractedUnits: 0,
            priority: .normal,
            fueledMinutes: 0,
            placedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func location(
        at coordinate: CLLocationCoordinate2D,
        timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp
        )
    }

    private func temporaryURL(_ stem: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-\(stem)-\(UUID().uuidString).sqlite")
        URLs.append(url)
        return url
    }
}
