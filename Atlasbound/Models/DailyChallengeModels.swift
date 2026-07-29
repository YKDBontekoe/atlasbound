import Foundation

enum DailyChallengeKind: String, CaseIterable, Sendable {
    case discover
    case revisit
    case route
}

struct DailyChallengeGoal: Identifiable, Sendable, Equatable {
    let kind: DailyChallengeKind
    let currentValue: Int
    let targetValue: Int

    var id: String { kind.rawValue }
    var isComplete: Bool { currentValue >= targetValue }
    var progressFraction: Double {
        guard targetValue > 0 else { return 1 }
        return min(1, Double(currentValue) / Double(targetValue))
    }
}

struct DailyChallengeSnapshot: Sendable, Equatable {
    let dayKey: String
    let goals: [DailyChallengeGoal]

    var completedGoalCount: Int { goals.filter(\.isComplete).count }
    var isComplete: Bool { !goals.isEmpty && completedGoalCount == goals.count }
    var progressFraction: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.reduce(0) { $0 + $1.progressFraction } / Double(goals.count)
    }
    var primaryGoal: DailyChallengeGoal? {
        goals.first { !$0.isComplete } ?? goals.first
    }
}
