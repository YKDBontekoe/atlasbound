import XCTest
@testable import Atlasbound

final class FactoryEngineTests: XCTestCase {
    private let tileEngine = TileEngine(option: .twenty)

    func testDepositsAreDeterministicAndNeverPersistGeometry() {
        let engine = ConstructionEngine()
        let tileID = TileEngine.makeTileID(q: 14, r: -8, sizeMeters: 20)
        XCTAssertEqual(engine.deposit(for: tileID), engine.deposit(for: tileID))

        for q in 0..<100 {
            let deposit = engine.deposit(
                for: TileEngine.makeTileID(q: q, r: -q, sizeMeters: 20)
            )
            if deposit.kind == .empty {
                XCTAssertEqual(deposit.capacity, 0)
            } else {
                XCTAssertTrue((300...600).contains(deposit.capacity))
                XCTAssertNotNil(deposit.kind.outputItemID)
            }
        }
    }

    func testPlacementRequiresExplorationProximityAndCompatibleDeposit() {
        let engine = ConstructionEngine()
        let targetID = yieldingTileID()
        let coordinate = try! XCTUnwrap(tileEngine.parseTileID(targetID))
        let now = Date(timeIntervalSince1970: 10_000)
        let definition = try! XCTUnwrap(FactoryCatalog.byID["gathering_outpost"])
        let explored = WorldTile(
            id: targetID,
            coordinate: coordinate,
            state: .explored,
            masteryXP: 150,
            visitCount: 2
        )

        XCTAssertTrue(
            engine.validatePlacement(
                definition: definition,
                targetTile: explored,
                playerTile: coordinate,
                locationTimestamp: now,
                now: now,
                structures: [:],
                unlockedResearchIDs: ["foundations"],
                availableKitCount: 1,
                tileEngine: tileEngine
            ).isAllowed
        )

        let stale = engine.validatePlacement(
            definition: definition,
            targetTile: explored,
            playerTile: coordinate,
            locationTimestamp: now.addingTimeInterval(-121),
            now: now,
            structures: [:],
            unlockedResearchIDs: ["foundations"],
            availableKitCount: 1,
            tileEngine: tileEngine
        )
        XCTAssertFalse(stale.isAllowed)

        var discoveredOnly = explored
        discoveredOnly.state = .discovered
        XCTAssertFalse(
            engine.validatePlacement(
                definition: definition,
                targetTile: discoveredOnly,
                playerTile: coordinate,
                locationTimestamp: now,
                now: now,
                structures: [:],
                unlockedResearchIDs: ["foundations"],
                availableKitCount: 1,
                tileEngine: tileEngine
            ).isAllowed
        )
    }

    func testRoadNetworksAndShortestPathAreDeterministic() {
        let roads = [
            structure(q: 0, r: 0, definitionID: "trail_road"),
            structure(q: 1, r: 0, definitionID: "trail_road"),
            structure(q: 2, r: 0, definitionID: "paved_road"),
        ]
        let source = structure(q: -1, r: 1, definitionID: "trailhead_depot")
        let destination = structure(q: 3, r: -1, definitionID: "atlas_refinery")
        let isolated = structure(q: 20, r: 20, definitionID: "trail_road")
        let all = Dictionary(
            uniqueKeysWithValues: (roads + [source, destination, isolated]).map { ($0.tileID, $0) }
        )

        let engine = FactoryNetworkEngine()
        let networks = engine.networks(structures: all, tileEngine: tileEngine)
        XCTAssertEqual(networks.count, 2)
        let connected = try! XCTUnwrap(networks.first { $0.buildingTileIDs.count == 2 })
        XCTAssertEqual(connected.totalRoadCapacity, 40)
        let first = engine.shortestRoadPath(
            fromBuildingID: source.tileID,
            toBuildingID: destination.tileID,
            network: connected,
            tileEngine: tileEngine
        )
        let second = engine.shortestRoadPath(
            fromBuildingID: source.tileID,
            toBuildingID: destination.tileID,
            network: connected,
            tileEngine: tileEngine
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first?.count, 3)
    }

    func testSimulationPowersExtractorRoutesOutputAndBurnsFuel() {
        let start = Date(timeIntervalSince1970: 20_000)
        let extractorTileID = yieldingTileID(adjacentTo: TileCoordinate(q: 0, r: 0))
        let extractorCoordinate = try! XCTUnwrap(tileEngine.parseTileID(extractorTileID))
        let roadCoordinate = try! XCTUnwrap(
            tileEngine.neighbors(of: extractorCoordinate).first
        )
        let generatorCoordinate = try! XCTUnwrap(
            tileEngine.neighbors(of: roadCoordinate).first { $0 != extractorCoordinate }
        )
        let depotCoordinate = try! XCTUnwrap(
            tileEngine.neighbors(of: roadCoordinate).first {
                $0 != extractorCoordinate && $0 != generatorCoordinate
            }
        )

        var road = structure(coordinate: roadCoordinate, definitionID: "waystone_road")
        road.tier = 3
        let extractor = structure(coordinate: extractorCoordinate, definitionID: "gathering_outpost")
        let generator = structure(coordinate: generatorCoordinate, definitionID: "waystone_dynamo")
        var depot = structure(coordinate: depotCoordinate, definitionID: "grand_depot")
        depot.outputBuffer = ["amber_resin": 2]
        var state = FactoryState.empty(at: start)
        state.structures = Dictionary(
            uniqueKeysWithValues: [road, extractor, generator, depot].map { ($0.tileID, $0) }
        )

        let next = FactorySimulationEngine().advance(
            state: state,
            to: start.addingTimeInterval(60),
            tileEngine: tileEngine
        )
        let deposit = ConstructionEngine().deposit(for: extractor.tileID)
        XCTAssertEqual(next.structures[extractor.tileID]?.extractedUnits, 1)
        XCTAssertEqual(next.lifetimeProduced[deposit.kind.outputItemID!], 1)
        XCTAssertEqual(next.structures[generator.tileID]?.fueledMinutes, 9)
    }

    func testSimulationIsChunkEquivalentAndCapsOfflineProgress() {
        let start = Date(timeIntervalSince1970: 30_000)
        let state = poweredRefineryState(start: start)
        let engine = FactorySimulationEngine()
        let direct = engine.advance(
            state: state,
            to: start.addingTimeInterval(4 * 60 * 60),
            tileEngine: tileEngine
        )
        let halfway = engine.advance(
            state: state,
            to: start.addingTimeInterval(2 * 60 * 60),
            tileEngine: tileEngine
        )
        let chunked = engine.advance(
            state: halfway,
            to: start.addingTimeInterval(4 * 60 * 60),
            tileEngine: tileEngine
        )
        XCTAssertEqual(direct, chunked)

        let farFuture = start.addingTimeInterval(12 * 60 * 60)
        let capped = engine.advance(state: state, to: farFuture, tileEngine: tileEngine)
        XCTAssertEqual(capped.lastSimulatedAt, farFuture)
    }

    func testFoundationsCanProduceInsightBeforeMechanics() {
        let recipe = try! XCTUnwrap(FactoryRecipeCatalog.byID["bind_field_insight"])
        XCTAssertNil(recipe.requiredResearchID)
        XCTAssertTrue(recipe.inputs.contains { $0.itemID == "sector_dust" })
        XCTAssertFalse(recipe.inputs.contains { $0.itemID == "mechanism" })
        XCTAssertTrue(
            FactoryCatalog.byID["research_observatory"]?.allowedRecipeIDs.contains(recipe.id) == true
        )

        let efficient = try! XCTUnwrap(FactoryRecipeCatalog.byID["bind_atlas_insight"])
        XCTAssertEqual(efficient.requiredResearchID, "mechanics")
    }

    private func poweredRefineryState(start: Date) -> FactoryState {
        var road = structure(q: 0, r: 0, definitionID: "waystone_road")
        road.tier = 3
        let generator = structure(q: -1, r: 0, definitionID: "waystone_dynamo")
        var refinery = structure(q: 0, r: 1, definitionID: "atlas_refinery")
        refinery.selectedRecipeID = "refine_stone_block"
        var depot = structure(q: 1, r: 0, definitionID: "grand_depot")
        depot.outputBuffer = ["amber_resin": 100, "cobble_chip": 500]
        var state = FactoryState.empty(at: start)
        state.structures = Dictionary(
            uniqueKeysWithValues: [road, generator, refinery, depot].map { ($0.tileID, $0) }
        )
        return state
    }

    private func yieldingTileID(adjacentTo anchor: TileCoordinate? = nil) -> String {
        let candidates = anchor.map(tileEngine.neighbors(of:)) ?? (0..<100).map {
            TileCoordinate(q: $0, r: -$0)
        }
        return candidates.map {
            TileEngine.makeTileID(q: $0.q, r: $0.r, sizeMeters: tileEngine.tileSizeMeters)
        }.first {
            ConstructionEngine().deposit(for: $0).kind != .empty
        }!
    }

    private func structure(q: Int, r: Int, definitionID: String) -> PlacedFactoryStructure {
        structure(coordinate: TileCoordinate(q: q, r: r), definitionID: definitionID)
    }

    private func structure(
        coordinate: TileCoordinate,
        definitionID: String
    ) -> PlacedFactoryStructure {
        let id = TileEngine.makeTileID(
            q: coordinate.q,
            r: coordinate.r,
            sizeMeters: tileEngine.tileSizeMeters
        )
        return PlacedFactoryStructure(
            tileID: id,
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
}
