import Foundation

/// Derives a fresh local-day challenge from canonical visit timestamps.
struct DailyChallengeEngine: Sendable {
    static let discoveryTarget = 5
    static let revisitTarget = 3
    static let routeTarget = 12

    func snapshot(
        tiles: [WorldTile],
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> DailyChallengeSnapshot {
        let discoveredToday = tiles.lazy.filter { tile in
            guard tile.isDiscovered, let firstVisit = tile.firstVisitedAt else { return false }
            return calendar.isDate(firstVisit, inSameDayAs: date)
        }.count

        let revisitedToday = tiles.lazy.filter { tile in
            guard
                tile.isDiscovered,
                let firstVisit = tile.firstVisitedAt,
                let lastVisit = tile.lastVisitedAt
            else {
                return false
            }
            return !calendar.isDate(firstVisit, inSameDayAs: date)
                && calendar.isDate(lastVisit, inSameDayAs: date)
        }.count

        let uniqueTilesToday = tiles.lazy.filter { tile in
            guard tile.isDiscovered, let lastVisit = tile.lastVisitedAt else { return false }
            return calendar.isDate(lastVisit, inSameDayAs: date)
        }.count

        return DailyChallengeSnapshot(
            dayKey: Self.dayKey(for: date, calendar: calendar),
            goals: [
                DailyChallengeGoal(
                    kind: .discover,
                    currentValue: discoveredToday,
                    targetValue: Self.discoveryTarget
                ),
                DailyChallengeGoal(
                    kind: .revisit,
                    currentValue: revisitedToday,
                    targetValue: Self.revisitTarget
                ),
                DailyChallengeGoal(
                    kind: .route,
                    currentValue: uniqueTilesToday,
                    targetValue: Self.routeTarget
                ),
            ]
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
