import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class FactorySnapshotTests: XCTestCase {
    private var URLs: [URL] = []

    override func tearDown() {
        for url in URLs {
            try? FileManager.default.removeItem(at: url)
        }
        URLs = []
        super.tearDown()
    }

    func testFactoryOverviewSnapshot() throws {
        let controller = makeController()
        try SnapshotSupport.assertSnapshot(
            of: FactoryTabView(controller: controller),
            named: "FactoryOverview"
        )
    }

    func testFactoryRecipeBookSnapshot() throws {
        let controller = makeController()
        try SnapshotSupport.assertSnapshot(
            of: NavigationStack {
                FactoryRecipeBookView(controller: controller)
            },
            named: "FactoryRecipeBook"
        )
    }

    func testFactoryResearchSnapshot() throws {
        let controller = makeController()
        try SnapshotSupport.assertSnapshot(
            of: NavigationStack {
                FactoryResearchView(controller: controller)
            },
            named: "FactoryResearch"
        )
    }

    func testFactoryStructureInspectorSnapshot() throws {
        let controller = makeController()
        let depotID = TileEngine.makeTileID(q: 1, r: 0, sizeMeters: 20)
        try SnapshotSupport.assertSnapshot(
            of: FactoryStructureInspector(controller: controller, tileID: depotID),
            named: "FactoryStructureInspector"
        )
    }

    func testFactoryTutorialSnapshot() throws {
        try SnapshotSupport.assertSnapshot(
            of: FactoryTutorialView(onComplete: {}),
            named: "FactoryTutorial"
        )
    }

    func testFactoryHelpSnapshot() throws {
        try SnapshotSupport.assertSnapshot(
            of: FactoryHelpSheet(onReplayTutorial: {}),
            named: "FactoryHelp"
        )
    }

    func testFactoryViewsRenderAtLargeText() throws {
        let controller = makeController()
        try SnapshotSupport.assertRenders(
            FactoryTabView(controller: controller)
                .environment(\.sizeCategory, .accessibilityLarge),
            size: SnapshotSupport.canvasSize
        )
        try SnapshotSupport.assertRenders(
            FactoryTutorialView(onComplete: {})
                .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge),
            size: SnapshotSupport.canvasSize
        )
    }

    private func makeController() -> FactoryController {
        let tileStore = TileStore(
            fileURL: temporaryURL("factory-snapshot-world"),
            installationID: "factory-snapshot"
        )
        let inventory = InventoryStore(fileURL: temporaryURL("factory-snapshot-inventory"))
        inventory.deposit([
            ItemAmount(itemID: "cobble_chip", quantity: 12),
            ItemAmount(itemID: "trail_road_kit", quantity: 3),
            ItemAmount(itemID: "atlas_insight", quantity: 8),
        ])
        let store = FactoryStore(
            fileURL: temporaryURL("factory-snapshot-state"),
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let structures = [
            makeStructure(q: 0, r: 0, definitionID: "trail_road"),
            makeStructure(q: 1, r: 0, definitionID: "trailhead_depot", output: ["cobble_chip": 42, "amber_resin": 8]),
            makeStructure(q: 0, r: 1, definitionID: "waystone_dynamo", input: ["amber_resin": 1]),
            makeStructure(q: -1, r: 1, definitionID: "atlas_refinery", selectedRecipeID: "refine_stone_block"),
        ]
        store.update {
            $0.structures = Dictionary(uniqueKeysWithValues: structures.map { ($0.tileID, $0) })
            $0.unlockedResearchIDs.insert("logistics_1")
            $0.lifetimeProduced = ["cobble_chip": 128, "stone_block": 24]
        }
        return FactoryController(store: store, tileStore: tileStore, inventoryStore: inventory)
    }

    private func makeStructure(
        q: Int,
        r: Int,
        definitionID: String,
        input: [String: Int] = [:],
        output: [String: Int] = [:],
        selectedRecipeID: String? = nil
    ) -> PlacedFactoryStructure {
        PlacedFactoryStructure(
            tileID: TileEngine.makeTileID(q: q, r: r, sizeMeters: 20),
            definitionID: definitionID,
            tier: 1,
            inputBuffer: input,
            outputBuffer: output,
            selectedRecipeID: selectedRecipeID,
            recipeProgressMinutes: 1,
            extractedUnits: 0,
            priority: .normal,
            fueledMinutes: definitionID == "waystone_dynamo" ? 7 : 0,
            placedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func temporaryURL(_ stem: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(stem)-\(UUID().uuidString).json")
        URLs.append(url)
        return url
    }
}
