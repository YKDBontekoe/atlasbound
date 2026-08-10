import XCTest
@testable import Atlasbound

@MainActor
final class PulseStoreTests: XCTestCase {
    func testPulseStatePersistsAndInteractionIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlasbound-pulse-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let database = AtlasDatabase.makeIsolated(fileURL: url)
        let store = PulseStore(database: database)
        let tileEngine = TileEngine(option: .twenty)
        let anchor = TileCoordinate(q: 0, r: 0)
        let now = Date(timeIntervalSince1970: 1_754_832_000)
        store.refresh(around: anchor, tileEngine: tileEngine, at: now)

        let pulse = try XCTUnwrap(store.activePulses.first)
        let pulseTile = try XCTUnwrap(tileEngine.parseTileID(pulse.anchorTileID))
        let first = store.perform(
            pulseID: pulse.id,
            action: .observe,
            playerTile: pulseTile,
            tileEngine: tileEngine,
            at: now
        )
        let second = store.perform(
            pulseID: pulse.id,
            action: .observe,
            playerTile: pulseTile,
            tileEngine: tileEngine,
            at: now
        )

        guard case .completed = first else {
            return XCTFail("Expected the first interaction to complete")
        }
        guard case .denied = second else {
            return XCTFail("Expected the second interaction to be rejected")
        }

        let reloaded = PulseStore(database: database, now: now)
        XCTAssertEqual(reloaded.state.interactions.count, 1)
        XCTAssertEqual(reloaded.state.interactions.first?.pulseID, pulse.id)

        reloaded.advance(at: now.addingTimeInterval(60 * 60))
        reloaded.refresh(around: anchor, tileEngine: tileEngine, at: now.addingTimeInterval(60 * 60))
        XCTAssertFalse(reloaded.activePulses.contains { $0.id == pulse.id })
    }
}
