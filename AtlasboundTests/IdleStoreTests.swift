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
        let worldURL = temporaryURL("world")
        let inventoryURL = temporaryURL("inventory")
        let idleURL = temporaryURL("idle-world")
        let start = Date(timeIntervalSince1970: 5_000_000)
        let tileStore = TileStore(fileURL: worldURL, installationID: "idle-controller-tests")
        let inventory = InventoryStore(fileURL: inventoryURL)
        let idleStore = IdleStore(fileURL: idleURL, now: start)
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
        let report = controller.advanceIdle(to: start.addingTimeInterval(60 * 60))
        XCTAssertEqual(report.simulatedMinutes, 60)
        XCTAssertEqual(inventory.quantity(of: "cobble_chip"), 2)
        XCTAssertEqual(inventory.quantity(of: "moss_scrap"), 2)
    }

    private func temporaryURL(_ stem: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-\(stem)-\(UUID().uuidString).sqlite")
        urls.append(url)
        return url
    }
}
