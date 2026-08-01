import XCTest
import SwiftUI
@testable import Atlasbound

@MainActor
final class JournalSnapshotTests: XCTestCase {
    private var URLs: [URL] = []

    override func tearDown() {
        for url in URLs {
            try? FileManager.default.removeItem(at: url)
        }
        URLs = []
        super.tearDown()
    }

    func testJournalEmptyChromeSnapshot() throws {
        let harness = makeHarness(populate: false)
        try SnapshotSupport.assertSnapshot(
            of: JournalTabView(
                controller: harness.controller,
                store: harness.store,
                activityHistory: harness.history,
                treasureStore: harness.treasure
            ),
            named: "JournalEmpty"
        )
    }

    func testJournalPopulatedChromeSnapshot() throws {
        let harness = makeHarness(populate: true)
        try SnapshotSupport.assertSnapshot(
            of: JournalTabView(
                controller: harness.controller,
                store: harness.store,
                activityHistory: harness.history,
                treasureStore: harness.treasure
            ),
            named: "JournalPopulated"
        )
    }

    func testJournalRendersAtLargeText() throws {
        let harness = makeHarness(populate: true)
        try SnapshotSupport.assertRenders(
            JournalTabView(
                controller: harness.controller,
                store: harness.store,
                activityHistory: harness.history,
                treasureStore: harness.treasure
            )
            .environment(\.sizeCategory, .accessibilityLarge),
            size: SnapshotSupport.canvasSize
        )
    }

    func testAtlasEmptyStatePrimitiveSnapshot() throws {
        let view = StatSectionCard {
            AtlasEmptyState(
                title: "Pack is empty",
                message: "Explore tiles to gather field finds — materials, boosts, and charges.",
                systemImage: "shippingbox",
                accent: AtlasTheme.teal,
                actionTitle: "Assemble…",
                action: {}
            )
        }
        .padding()
        .background(AtlasTheme.canvas)
        .frame(width: 390, height: 320)

        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "AtlasEmptyState",
            size: CGSize(width: 390, height: 320)
        )
    }

    func testAtlasSectionHeaderPrimitiveSnapshot() throws {
        let view = StatSectionCard {
            VStack(alignment: .leading, spacing: AtlasTheme.Space.md) {
                AtlasSectionHeader(
                    title: "Inventory",
                    subtitle: "Field finds, materials, and charges from the trail.",
                    systemImage: "shippingbox.fill",
                    accent: AtlasTheme.teal
                )
                AtlasMetricRow(label: "Finds today", value: "2/8", systemImage: "sparkles")
                AtlasMetricRow(label: "Lifetime finds", value: "42")
            }
        }
        .padding()
        .background(AtlasTheme.canvas)
        .frame(width: 390, height: 220)

        try SnapshotSupport.assertSnapshot(
            of: view,
            named: "AtlasSectionHeader",
            size: CGSize(width: 390, height: 220)
        )
    }

    // MARK: - Harness

    private struct Harness {
        let controller: WorldController
        let store: TileStore
        let history: ActivityHistoryStore
        let treasure: TreasureStore
    }

    private func makeHarness(populate: Bool) -> Harness {
        let store = TileStore(
            fileURL: temporaryURL("journal-snapshot-world"),
            installationID: "journal-snapshot"
        )
        let history = ActivityHistoryStore(fileURL: temporaryURL("journal-snapshot-history"))
        let treasure = TreasureStore(fileURL: temporaryURL("journal-snapshot-treasure"))
        let inventory = InventoryStore(fileURL: temporaryURL("journal-snapshot-inventory"))

        if populate {
            inventory.deposit([
                ItemAmount(itemID: "cobble_chip", quantity: 6),
                ItemAmount(itemID: "amber_resin", quantity: 2),
            ])
            store.upsert(
                WorldTile(
                    id: "hex:20:0:0",
                    coordinate: TileCoordinate(q: 0, r: 0),
                    state: .explored,
                    masteryXP: 40,
                    visitCount: 2,
                    firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_400)
                )
            )
            store.upsert(
                WorldTile(
                    id: "hex:20:1:0",
                    coordinate: TileCoordinate(q: 1, r: 0),
                    state: .discovered,
                    masteryXP: 10,
                    visitCount: 1,
                    firstVisitedAt: Date(timeIntervalSince1970: 1_700_000_200),
                    lastVisitedAt: Date(timeIntervalSince1970: 1_700_000_200)
                )
            )
            history.record(
                ActivitySummary(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    endedAt: Date(timeIntervalSince1970: 1_700_001_800),
                    distanceMeters: 2_450,
                    sampleCount: 80,
                    tilesVisited: 12,
                    tilesDiscovered: 4,
                    discoveryXP: 400,
                    familiarityXP: 60,
                    activityType: .walk,
                    frontierContribution: nil
                )
            )
        }

        let controller = WorldController(
            store: store,
            activityHistory: history,
            treasureStore: treasure,
            inventoryStore: inventory
        )
        return Harness(controller: controller, store: store, history: history, treasure: treasure)
    }

    private func temporaryURL(_ label: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString).json")
        URLs.append(url)
        URLs.append(url.deletingPathExtension().appendingPathExtension("sqlite"))
        return url
    }
}
