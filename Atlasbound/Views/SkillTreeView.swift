import SwiftUI

/// Compact Progress-tab entry for the infinite skill tree.
struct SkillTreeCard: View {
    let snapshot: SkillTreeSnapshot
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            StatSectionCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(AtlasTheme.teal.opacity(0.16))
                                .frame(width: 36, height: 36)
                            Image(systemName: "tree.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(AtlasTheme.teal)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Skill Tree")
                                .font(.subheadline.weight(.semibold))
                            Text(pointsLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        ForEach(SkillDiscipline.allCases) { discipline in
                            VStack(spacing: 4) {
                                Image(systemName: discipline.symbolName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AtlasTheme.blue)
                                Text("\(snapshot.disciplineRanks[discipline] ?? 0)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                Text(discipline.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("skillTreeCard")
        .accessibilityLabel("Skill tree, \(snapshot.pointsAvailable) points available")
    }

    private var pointsLabel: String {
        if snapshot.pointsAvailable > 0 {
            return "\(snapshot.pointsAvailable) point\(snapshot.pointsAvailable == 1 ? "" : "s") ready to spend"
        }
        if snapshot.pointsSpent == 0 {
            return "Earn Skill Points as you level up"
        }
        return "\(snapshot.pointsSpent) spent · keep exploring to earn more"
    }
}

struct SkillTreeView: View {
    @ObservedObject var controller: WorldController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var snapshot: SkillTreeSnapshot {
        controller.skillTreeSnapshot
    }

    private let engine = SkillTreeEngine()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    ForEach(SkillDiscipline.allCases) { discipline in
                        disciplineSection(discipline)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(AtlasTheme.canvas.ignoresSafeArea())
            .navigationTitle("Skill Tree")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Skill Points")
                    .font(.caption2.weight(.bold))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snapshot.pointsAvailable)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                    Text("available")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Earned \(snapshot.pointsEarned)")
                        Text("Spent \(snapshot.pointsSpent)")
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                Text("One Skill Point per explorer level. Ranks are permanent and scale forever with diminishing returns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func disciplineSection(_ discipline: SkillDiscipline) -> some View {
        StatSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: discipline.symbolName)
                        .foregroundStyle(AtlasTheme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(discipline.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(discipline.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("R\(snapshot.disciplineRanks[discipline] ?? 0)")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(AtlasTheme.teal)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AtlasTheme.teal.opacity(0.12), in: Capsule())
                }

                ForEach(SkillTreeCatalog.nodes(for: discipline)) { node in
                    skillNodeRow(node)
                }
            }
        }
    }

    private func skillNodeRow(_ node: SkillNodeDefinition) -> some View {
        let rank = snapshot.ranks[node.id] ?? 0
        let cost = engine.costToRankUp(from: rank)
        let canRank = {
            if case .ranked = engine.canRankUp(
                nodeID: node.id,
                state: controller.skillStore.state,
                explorerLevel: snapshot.explorerLevel
            ).outcome {
                return true
            }
            return false
        }()
        let denial: String? = {
            if case .denied(let message) = engine.canRankUp(
                nodeID: node.id,
                state: controller.skillStore.state,
                explorerLevel: snapshot.explorerLevel
            ).outcome {
                return message
            }
            return nil
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: node.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(rank > 0 ? AtlasTheme.blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(node.name)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(rank > 0 ? "Rank \(rank)" : "Locked")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(rank > 0 ? AtlasTheme.teal : .secondary)
                    }
                    Text(node.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(engine.bonusDescription(for: node, rank: max(rank, 1)))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AtlasTheme.blue)
                    if let denial, !canRank {
                        Text(denial)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                AtlasMotion.withOptionalAnimation(AtlasMotion.panel, reduceMotion: reduceMotion) {
                    _ = controller.rankUpSkill(node.id)
                }
            } label: {
                Text(rank == 0 ? "Unlock · \(cost) SP" : "Rank up · \(cost) SP")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(AtlasTheme.blue)
            .disabled(!canRank)
            .accessibilityIdentifier("skillRankUp_\(node.id)")
        }
        .padding(.vertical, 4)
    }
}
