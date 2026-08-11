import XCTest
@testable import Atlasbound

final class CrewfrontBattleEngineTests: XCTestCase {
    func testStarterDeckIsValidAndTrainingStarts() throws {
        let state = CardState.empty(now: Date(timeIntervalSince1970: 100))
        let deck = try XCTUnwrap(state.decks.first)
        let engine = CrewfrontBattleEngine()
        XCTAssertNil(engine.validate(deck: deck, instances: state.instances))
        let battle = try XCTUnwrap(engine.startTraining(deck: deck, instances: state.instances, now: Date(timeIntervalSince1970: 101)))
        XCTAssertEqual(battle.round, 1)
        XCTAssertEqual(battle.guardianDurability, 8)
        XCTAssertEqual(battle.participants.count, 2)
    }

    func testDeckRejectsMissingAndDuplicateInstances() {
        let state = CardState.empty()
        let deck = state.decks[0]
        var invalid = deck
        invalid.cardInstanceIDs[1] = invalid.cardInstanceIDs[0]
        XCTAssertNotNil(CrewfrontBattleEngine().validate(deck: invalid, instances: state.instances))
    }

    func testDeckAllowsAtMostTwoCopiesOfBlueprint() {
        var state = CardState.empty()
        let prototype = state.instances[0]
        let first = CardInstance(id: UUID(), blueprintID: prototype.blueprintID, integrity: .ready, isProtected: false, craftedAt: .now)
        let second = CardInstance(id: UUID(), blueprintID: prototype.blueprintID, integrity: .ready, isProtected: false, craftedAt: .now)
        state.instances.append(contentsOf: [first, second])
        var deck = state.decks[0]
        deck.cardInstanceIDs[1] = first.id
        deck.cardInstanceIDs[2] = second.id
        XCTAssertNotNil(CrewfrontBattleEngine().validate(deck: deck, instances: state.instances))
    }

    func testTacticDamagesGuardianAndVictoryIsDeterministic() throws {
        let now = Date(timeIntervalSince1970: 200)
        let state = CardState.empty(now: now)
        let deck = try XCTUnwrap(state.decks.first)
        let engine = CrewfrontBattleEngine()
        var battle = try XCTUnwrap(engine.startTraining(deck: deck, instances: state.instances, now: now))
        let spark = try XCTUnwrap(state.instances.first { $0.blueprintID == "artificer_spark" })
        let playerIndex = try XCTUnwrap(battle.participants.indices.first { !battle.participants[$0].isAI })
        battle.participants[playerIndex].hand = [spark.id]
        battle.participants[playerIndex].energy = 3
        let player = battle.participants[playerIndex]
        battle.guardianDurability = 2
        let result = engine.resolve(
            state: battle,
            actions: [PlannedBattleAction(id: UUID(), participantID: player.id, kind: .reinforce, cardInstanceID: spark.id, targetHex: .center, submittedAt: now)],
            instances: state.instances,
            now: now
        )
        XCTAssertEqual(result.guardianDurability, 0)
        XCTAssertEqual(result.winner, .dawn)
    }
}
