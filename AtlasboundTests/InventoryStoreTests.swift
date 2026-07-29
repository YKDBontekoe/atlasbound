import XCTest
@testable import Atlasbound

@MainActor
final class InventoryStoreTests: XCTestCase {
    private var fileURL: URL!
    private var store: InventoryStore!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-inventory-\(UUID().uuidString).json")
        store = InventoryStore(fileURL: fileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
        store = nil
        fileURL = nil
        super.tearDown()
    }

    func testCollectMergesStacksAndClaimsOnce() {
        let find = FieldFind(
            id: "find:2026-07-29:hex:20:1:2",
            tileID: "hex:20:1:2",
            dayKey: "2026-07-29",
            itemID: "moss_scrap",
            quantity: 2,
            isDiscoveryDrop: true
        )
        XCTAssertNotNil(store.collect(find))
        XCTAssertEqual(store.quantity(of: "moss_scrap"), 2)
        XCTAssertNotNil(store.latestPickup)
        XCTAssertNil(store.collect(find))
        XCTAssertEqual(store.quantity(of: "moss_scrap"), 2)
        XCTAssertEqual(store.lifetimeFindsCollected, 1)
    }

    func testProcessVisitedClaimsDeterministicFind() {
        let engine = FieldFindEngine()
        let dayKey = engine.localDayKey()
        var claimedTile: String?
        for q in 0..<80 {
            let tileID = TileEngine.makeTileID(q: q, r: 1, sizeMeters: 20)
            if engine.rollFind(
                tileID: tileID,
                isDiscovery: true,
                dayKey: dayKey,
                claimedFindIDs: [],
                findsClaimedToday: 0
            ) != nil {
                claimedTile = tileID
                break
            }
        }
        guard let tileID = claimedTile else {
            XCTFail("Expected a yielding tile")
            return
        }

        store.processVisitedTileIDs([tileID], discoveryTileIDs: [tileID])
        XCTAssertNotNil(store.latestPickup)
        XCTAssertEqual(store.findsClaimedToday, 1)
        store.dismissPickup()
        store.processVisitedTileIDs([tileID], discoveryTileIDs: [tileID])
        XCTAssertNil(store.latestPickup)
    }

    func testUsePathbreadGrantsFamiliarityXP() {
        _ = store.collect(
            FieldFind(
                id: "find:test:pathbread",
                tileID: "hex:20:0:0",
                dayKey: "test",
                itemID: "pathbread",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        let result = store.useItem(itemID: "pathbread")
        XCTAssertEqual(result?.grantedFamiliarityXP, FieldFindConstants.pathbreadFamiliarityXP)
        XCTAssertEqual(store.quantity(of: "pathbread"), 0)
    }

    func testUseFamiliarityTonicStartsEffect() {
        _ = store.collect(
            FieldFind(
                id: "find:test:tonic",
                tileID: "hex:20:0:1",
                dayKey: "test",
                itemID: "familiarity_tonic",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        XCTAssertNotNil(store.useItem(itemID: "familiarity_tonic"))
        XCTAssertTrue(store.activeEffects.contains { $0.kind == .familiarityBoost })
        let modified = store.applyXPModifiers(discovery: 0, familiarity: 20)
        XCTAssertEqual(modified.familiarity, 30)
    }

    func testActivateTrailRerollConsumesCharge() {
        _ = store.collect(
            FieldFind(
                id: "find:test:reroll",
                tileID: "hex:20:0:2",
                dayKey: "test",
                itemID: "trail_reroll_token",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        let result = store.activateItem(itemID: "trail_reroll_token")
        XCTAssertEqual(result?.action, .activate)
        XCTAssertEqual(store.quantity(of: "trail_reroll_token"), 0)
    }

    func testAssembleConsumesInputsAndAddsOutput() {
        let recipe = try! XCTUnwrap(ItemRecipes.recipe(id: "craft_waystone_charm"))
        for input in recipe.inputs {
            _ = store.collect(
                FieldFind(
                    id: "find:test:\(input.itemID)",
                    tileID: "hex:20:\(input.itemID.hashValue):0",
                    dayKey: "test",
                    itemID: input.itemID,
                    quantity: input.quantity,
                    isDiscoveryDrop: true
                )
            )
            store.dismissPickup()
        }
        let result = store.assemble(recipeID: recipe.id)
        XCTAssertEqual(result?.outputItemID, "waystone_charm")
        XCTAssertEqual(store.quantity(of: "waystone_charm"), 1)
        for input in recipe.inputs {
            XCTAssertEqual(store.quantity(of: input.itemID), 0)
        }
    }

    func testSalvageAndDiscard() {
        _ = store.collect(
            FieldFind(
                id: "find:test:flare",
                tileID: "hex:20:9:9",
                dayKey: "test",
                itemID: "discovery_flare",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        XCTAssertNotNil(store.salvage(itemID: "discovery_flare"))
        XCTAssertEqual(store.quantity(of: "discovery_flare"), 0)
        XCTAssertGreaterThan(store.stacks.filter { ItemCatalog.definition(for: $0.itemID)?.category == .material }.count, 0)

        _ = store.collect(
            FieldFind(
                id: "find:test:moss",
                tileID: "hex:20:9:8",
                dayKey: "test",
                itemID: "moss_scrap",
                quantity: 3,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        XCTAssertNotNil(store.discard(itemID: "moss_scrap", amount: 2))
        XCTAssertEqual(store.quantity(of: "moss_scrap"), 1)
    }

    func testPersistRoundTrip() {
        _ = store.collect(
            FieldFind(
                id: "find:2026-07-29:hex:20:4:4",
                tileID: "hex:20:4:4",
                dayKey: "2026-07-29",
                itemID: "brass_rivet",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        _ = store.useItem(itemID: "familiarity_tonic") // may be nil if not owned
        _ = store.collect(
            FieldFind(
                id: "find:2026-07-29:hex:20:5:5",
                tileID: "hex:20:5:5",
                dayKey: "2026-07-29",
                itemID: "familiarity_tonic",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        _ = store.useItem(itemID: "familiarity_tonic")

        let reloaded = InventoryStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.quantity(of: "brass_rivet"), 1)
        XCTAssertTrue(reloaded.activeEffects.contains { $0.kind == .familiarityBoost })
        XCTAssertTrue(reloaded.claimedFindIDs.contains("find:2026-07-29:hex:20:4:4"))
    }

    func testClearClaimedFindIDs() {
        _ = store.collect(
            FieldFind(
                id: "find:2026-07-29:hex:20:7:7",
                tileID: "hex:20:7:7",
                dayKey: "2026-07-29",
                itemID: "cobble_chip",
                quantity: 1,
                isDiscoveryDrop: true
            )
        )
        store.clearClaimedFindIDs()
        XCTAssertTrue(store.claimedFindIDs.isEmpty)
        XCTAssertEqual(store.findsClaimedToday, 0)
        XCTAssertEqual(store.quantity(of: "cobble_chip"), 1)
    }

    func testAtomicMultiItemConsumption() {
        _ = store.collect(
            FieldFind(
                id: "find:test:atomic",
                tileID: "hex:20:2:3",
                dayKey: "test",
                itemID: "cobble_chip",
                quantity: 2,
                isDiscoveryDrop: true
            )
        )
        store.dismissPickup()
        let request = [
            ItemAmount(itemID: "cobble_chip", quantity: 2),
            ItemAmount(itemID: "moss_scrap", quantity: 1),
        ]
        XCTAssertFalse(store.consume(request))
        XCTAssertEqual(store.quantity(of: "cobble_chip"), 2)
        store.deposit([ItemAmount(itemID: "moss_scrap", quantity: 1)])
        XCTAssertTrue(store.consume(request))
        XCTAssertEqual(store.quantity(of: "cobble_chip"), 0)
        XCTAssertEqual(store.quantity(of: "moss_scrap"), 0)
    }

    func testGrantFreeRerollOnTreasureStore() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-treasure-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let treasure = TreasureStore(fileURL: url)
        treasure.ensureTrail(anchor: TileCoordinate(q: 0, r: 0), tileEngine: TileEngine(option: .twenty))
        let before = treasure.dailyTrail?.freeRerollsRemaining ?? 0
        treasure.grantFreeReroll()
        XCTAssertEqual(treasure.dailyTrail?.freeRerollsRemaining, before + 1)
    }
}
