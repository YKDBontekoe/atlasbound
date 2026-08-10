import XCTest
@testable import Atlasbound

final class PulseEngineTests: XCTestCase {
    func testLocalPulsesAreDeterministicForAnchorAndSlot() {
        let engine = PulseEngine()
        let tileEngine = TileEngine(option: .twenty)
        let date = Date(timeIntervalSince1970: 1_754_832_000)
        let anchor = TileCoordinate(q: 12, r: -7)

        let first = engine.localPulses(around: anchor, tileEngine: tileEngine, at: date)
        let second = engine.localPulses(around: anchor, tileEngine: tileEngine, at: date)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 3)
        XCTAssertTrue(first.allSatisfy { $0.anchorTileID.hasPrefix("hex:20:") })
    }

    func testPulseMovesThroughPhasesAndExpires() {
        let engine = PulseEngine()
        let tileEngine = TileEngine(option: .twenty)
        let start = Date(timeIntervalSince1970: 1_754_832_000)
        let pulse = try! XCTUnwrap(engine.localPulses(
            around: TileCoordinate(q: 0, r: 0),
            tileEngine: tileEngine,
            at: start
        ).first)

        XCTAssertEqual(pulse.phase(at: pulse.startedAt), .detected)
        XCTAssertEqual(pulse.phase(at: pulse.startedAt.addingTimeInterval(2 * 60 * 60)), .developing)
        XCTAssertEqual(pulse.phase(at: pulse.startedAt.addingTimeInterval(4 * 60 * 60)), .peak)
        XCTAssertEqual(pulse.phase(at: pulse.expiresAt), .resolved)
    }

    func testInteractionRequiresProximityAndProducesOutcome() {
        let engine = PulseEngine()
        let tileEngine = TileEngine(option: .twenty)
        let date = Date(timeIntervalSince1970: 1_754_832_000)
        let anchor = TileCoordinate(q: 0, r: 0)
        let pulse = try! XCTUnwrap(engine.localPulses(around: anchor, tileEngine: tileEngine, at: date).first)
        let pulseTile = try! XCTUnwrap(tileEngine.parseTileID(pulse.anchorTileID))

        XCTAssertTrue(engine.canInteract(pulse, playerTile: pulseTile, tileEngine: tileEngine, at: date))
        XCTAssertFalse(engine.canInteract(pulse, playerTile: TileCoordinate(q: 100, r: 100), tileEngine: tileEngine, at: date))

        let outcome = engine.outcome(for: pulse, action: .observe)
        XCTAssertFalse(outcome.title.isEmpty)
        XCTAssertGreaterThan(outcome.rewardQuantity, 0)
    }

    func testConditionOutcomeHasBoundedLifetime() {
        let engine = PulseEngine()
        let tileEngine = TileEngine(option: .twenty)
        let date = Date(timeIntervalSince1970: 1_754_832_000)
        let pulse = try! XCTUnwrap(engine.localPulses(
            around: TileCoordinate(q: 0, r: 0),
            tileEngine: tileEngine,
            at: date
        ).first)
        let condition = try! XCTUnwrap(engine.condition(for: pulse, action: .observe, at: date))

        XCTAssertEqual(condition.effectiveUntil.timeIntervalSince(condition.effectiveFrom), 24 * 60 * 60)
        XCTAssertEqual(condition.sourcePulseID, pulse.id)
    }
}
