import XCTest
@testable import Atlasbound

@MainActor
final class IdleStoreTests: XCTestCase {
    private var urls: [URL] = []

    override func tearDown() {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        urls = []
        super.tearDown()
    }

    func testIdleStatePersistsHiredScoutsAndCircuitClaim() {
        let url = temporaryURL("idle")
        let now = Date(timeIntervalSince1970: 4_000_000)
        let store = IdleStore(fileURL: url, now: now)
        store.update { state in
            IdleScoutEngine().applyHire(
                definition: ScoutCatalog.byID["apprentice_scout"]!,
                state: &state,
                at: now
            )
            state.claimedCircuitRewardDayKey = "2026-08-01"
            state.scoutDiscoveriesToday = 4
            state.scoutDiscoveryDayKey = "2026-08-01"
        }

        let reloaded = IdleStore(fileURL: url, now: now)
        XCTAssertTrue(reloaded.state.isHired("apprentice_scout"))
        XCTAssertTrue(reloaded.state.isUnlocked("pathfinder_scout"))
        XCTAssertEqual(reloaded.state.claimedCircuitRewardDayKey, "2026-08-01")
        XCTAssertEqual(reloaded.state.scoutDiscoveriesToday, 4)
    }

    func testWorldControllerAdvanceIdleDepositsHomeDrip() {
        let start = Date(timeIntervalSince1970: 5_000_000)
        let (controller, inventory) = makeIdleController(at: start)
        let report = controller.advanceIdle(to: start.addingTimeInterval(60 * 60))
        XCTAssertEqual(report.simulatedMinutes, 60)
        XCTAssertEqual(inventory.quantity(of: "cobble_chip"), 2)
        XCTAssertEqual(inventory.quantity(of: "moss_scrap"), 2)
        XCTAssertNil(controller.latestIdleWatch)
    }

    func testCatchUpIdleOnForegroundPresentsWatchReport() throws {
        let start = Date(timeIntervalSince1970: 5_100_000)
        let (controller, inventory) = makeIdleController(at: start)

        let report = controller.catchUpIdleOnForeground(to: start.addingTimeInterval(60 * 60))
        XCTAssertTrue(report.hasGatheredRewards)
        XCTAssertEqual(inventory.quantity(of: "cobble_chip"), 2)

        let watch = try XCTUnwrap(controller.latestIdleWatch)
        XCTAssertEqual(watch.report.simulatedMinutes, 60)
        XCTAssertFalse(watch.report.homeDripItems.isEmpty)
        XCTAssertEqual(watch.scoutDiscoveriesToday, controller.idleState.scoutDiscoveriesToday)

        controller.dismissIdleWatch()
        XCTAssertNil(controller.latestIdleWatch)
    }

    func testCatchUpIdleOnForegroundSkipsEmptyTick() {
        let start = Date(timeIntervalSince1970: 5_200_000)
        let (controller, _) = makeIdleController(at: start)

        let report = controller.catchUpIdleOnForeground(to: start)
        XCTAssertEqual(report.simulatedMinutes, 0)
        XCTAssertFalse(report.hasGatheredRewards)
        XCTAssertNil(controller.latestIdleWatch)
    }

    private func makeIdleController(at start: Date) -> (WorldController, InventoryStore) {
        let tileStore = TileStore(fileURL: temporaryURL("world"), installationID: "idle-controller-tests")
        let inventory = InventoryStore(fileURL: temporaryURL("inventory"))
        let idleStore = IdleStore(fileURL: temporaryURL("idle-world"), now: start)
        idleStore.update { $0.lastSimulatedAt = start }

        let homeSector = HexSectorEngine.makeSectorID(q: 0, r: 0, sizeMeters: 20)
        tileStore.updateTerritoryState { state in
            var next = state
            next.homeSectorID = homeSector
            next.claims = [TerritoryClaim(sectorID: homeSector, claimedAt: start)]
            return next
        }

        let controller = WorldController(
            store: tileStore,
            activityHistory: ActivityHistoryStore(fileURL: temporaryURL("history")),
            inventoryStore: inventory,
            idleStore: idleStore
        )
        return (controller, inventory)
    }

    private func temporaryURL(_ stem: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-\(stem)-\(UUID().uuidString).sqlite")
        urls.append(url)
        return url
    }
}
