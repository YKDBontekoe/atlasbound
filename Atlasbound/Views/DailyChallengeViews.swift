import SwiftUI

struct DailyChallengeProgressCard: View {
    let snapshot: DailyChallengeSnapshot
    var canClaimReward: Bool = false
    var onClaimReward: (() -> Void)?

    var body: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 14) {
                DailyChallengeHeader(snapshot: snapshot)

                ForEach(Array(snapshot.goals.enumerated()), id: \.element.id) { index, goal in
                    if index > 0 {
                        Divider()
                    }
                    DailyChallengeGoalRow(goal: goal)
                }

                Text(
                    snapshot.isComplete
                        ? (canClaimReward
                            ? "Circuit complete — claim today’s scout chest."
                            : "Compass charged — today’s circuit chest is secured.")
                        : "Complete all three before your local day resets."
                )
                .font(.caption2.weight(.medium))
                .foregroundStyle(snapshot.isComplete ? AtlasTheme.teal : .secondary)

                if canClaimReward, let onClaimReward {
                    Button(action: onClaimReward) {
                        Label("Claim circuit chest", systemImage: "shippingbox.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.teal)
                    .accessibilityIdentifier("claimCircuitRewardButton")
                }
            }
        }
        .accessibilityIdentifier("dailyChallengeCard")
    }
}

struct DailyChallengeCompactTracker: View {
    let snapshot: DailyChallengeSnapshot

    var body: some View {
        HStack(spacing: 10) {
            DailyChallengeRing(snapshot: snapshot, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isComplete ? "Scout Circuit complete" : "Scout Circuit")
                    .font(.caption.weight(.semibold))
                if let goal = snapshot.primaryGoal {
                    Text(
                        snapshot.isComplete
                            ? "Compass charged for today"
                            : "\(goal.kind.title) · \(min(goal.currentValue, goal.targetValue))/\(goal.targetValue)"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: snapshot.isComplete ? "checkmark.seal.fill" : "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(snapshot.isComplete ? AtlasTheme.teal : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                weight: .regular
            )
        }
        .accessibilityElement(children: .combine)
    }
}

struct DailyChallengeSheet: View {
    @ObservedObject var controller: WorldController
    /// Seed snapshot from the presenter; live values come from the controller.
    let snapshot: DailyChallengeSnapshot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var liveSnapshot: DailyChallengeSnapshot {
        let live = controller.dailyChallengeSnapshot
        return live.dayKey == snapshot.dayKey ? live : snapshot
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AtlasTheme.blue.opacity(0.16), AtlasTheme.teal.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        AtlasArtMark(name: "ScoutCircuitMark", size: 120)
                            .opacity(0.20)
                        DailyChallengeRing(snapshot: liveSnapshot, size: 104)
                    }
                    .frame(width: 132, height: 132)
                    .padding(.top, 8)

                    VStack(spacing: 5) {
                        Text(liveSnapshot.isComplete ? "Circuit complete" : "Today’s Scout Circuit")
                            .font(.title2.weight(.bold))
                        Text(
                            liveSnapshot.isComplete
                                ? "You explored wide, returned to familiar ground, and kept moving."
                                : "Three small goals that reward a balanced day of exploration."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    }

                    DailyChallengeProgressCard(
                        snapshot: liveSnapshot,
                        canClaimReward: controller.canClaimCircuitReward,
                        onClaimReward: { _ = controller.claimCircuitReward() }
                    )

                    if liveSnapshot.isComplete {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Chest contents")
                                .font(.caption.weight(.semibold))
                            Text(IdleConstants.circuitReward.map { amount in
                                let name = ItemCatalog.definition(for: amount.itemID)?.name ?? amount.itemID
                                return "\(amount.quantity)× \(name)"
                            }.joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Daily Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DailyChallengeHeader: View {
    let snapshot: DailyChallengeSnapshot

    var body: some View {
        HStack(spacing: 11) {
            DailyChallengeRing(snapshot: snapshot, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Scout Circuit")
                    .font(.subheadline.weight(.semibold))
                Text(
                    snapshot.isComplete
                        ? "All goals complete"
                        : "\(snapshot.completedGoalCount) of \(snapshot.goals.count) goals complete"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int((snapshot.progressFraction * 100).rounded()))%")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(snapshot.isComplete ? AtlasTheme.teal : AtlasTheme.blue)
        }
    }
}

private struct DailyChallengeGoalRow: View {
    let goal: DailyChallengeGoal

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: goal.isComplete ? "checkmark" : goal.kind.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(goal.isComplete ? AtlasTheme.teal : goal.kind.tint)
                .frame(width: 34, height: 34)
                .background(
                    (goal.isComplete ? AtlasTheme.teal : goal.kind.tint).opacity(0.12),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.kind.title)
                            .font(.caption.weight(.semibold))
                        Text(goal.kind.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("\(min(goal.currentValue, goal.targetValue))/\(goal.targetValue)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(goal.isComplete ? AtlasTheme.teal : .secondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule()
                            .fill(goal.isComplete ? AtlasTheme.teal : goal.kind.tint)
                            .frame(width: proxy.size.width * goal.progressFraction)
                    }
                }
                .frame(height: 5)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DailyChallengeRing: View {
    let snapshot: DailyChallengeSnapshot
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: max(4, size * 0.1))
            Circle()
                .trim(from: 0, to: snapshot.progressFraction)
                .stroke(
                    snapshot.isComplete ? AtlasTheme.teal : AtlasTheme.blue,
                    style: StrokeStyle(lineWidth: max(4, size * 0.1), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Image(systemName: snapshot.isComplete ? "checkmark" : "safari.fill")
                .font(.system(size: size * 0.3, weight: .bold))
                .foregroundStyle(snapshot.isComplete ? AtlasTheme.teal : AtlasTheme.blue)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension DailyChallengeKind {
    var title: String {
        switch self {
        case .discover: "Break New Ground"
        case .revisit: "Familiar Paths"
        case .route: "Keep Moving"
        }
    }

    var detail: String {
        switch self {
        case .discover: "Discover 5 new tiles"
        case .revisit: "Return to 3 known tiles"
        case .route: "Visit 12 unique tiles today"
        }
    }

    var symbolName: String {
        switch self {
        case .discover: "sparkles"
        case .revisit: "arrow.trianglehead.2.clockwise.rotate.90"
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        }
    }

    var tint: Color {
        switch self {
        case .discover: AtlasTheme.teal
        case .revisit: AtlasTheme.gold
        case .route: AtlasTheme.blue
        }
    }
}
