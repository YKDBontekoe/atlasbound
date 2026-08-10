import SwiftUI

/// Compact idle roster summary for the Adventures stack.
struct IdleScoutsCard: View {
    @ObservedObject var controller: WorldController
    var onManageTap: () -> Void

    private var state: IdleState { controller.idleState }

    var body: some View {
        Button(action: onManageTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(AtlasTheme.teal.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AtlasTheme.teal)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Idle Scouts")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(rosterTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background {
                GlassChrome(
                    shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                    weight: .regular
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("idleScoutsCard")
        .accessibilityLabel("Idle scouts, \(state.hiredScouts.count) hired")
    }

    private var rosterTitle: String {
        if state.hiredScouts.isEmpty {
            return controller.territoryState.hasHomeBase ? "Hire your first scout" : "Needs Home Base"
        }
        return "\(state.hiredScouts.count) on roster · \(state.totalTilesPerHour)/h"
    }

    private var statusDetail: String {
        if !controller.territoryState.hasHomeBase {
            return "Claim a Home Base sector to send scouts into nearby fog."
        }
        if let report = state.lastReport, report.hasGatheredRewards {
            var parts: [String] = []
            if report.scoutDiscoveriesGranted > 0 {
                parts.append(
                    "uncovered \(report.scoutDiscoveriesGranted) tile\(report.scoutDiscoveriesGranted == 1 ? "" : "s")"
                )
            }
            let campGoods = report.homeDripItems.reduce(0) { $0 + $1.quantity }
            if campGoods > 0 {
                parts.append(
                    "gathered \(campGoods) camp good\(campGoods == 1 ? "" : "s")"
                )
            }
            return "Last watch \(parts.joined(separator: " · ")). Daily cap \(state.scoutDiscoveriesToday)/\(IdleConstants.dailyScoutDiscoveryCap)."
        }
        return "AFK discoveries near claims, capped at \(IdleConstants.dailyScoutDiscoveryCap)/day. Home Camp drips materials while you’re away."
    }
}

struct IdleScoutsSheet: View {
    @ObservedObject var controller: WorldController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var state: IdleState { controller.idleState }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if let report = state.lastReport, report.simulatedMinutes > 0 {
                        lastWatchCard(report)
                    }

                    scoutStanceCard

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Roster")
                            .font(.headline)
                        ForEach(ScoutCatalog.all) { scout in
                            scoutRow(scout)
                        }
                    }
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Idle Scouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                controller.advanceIdle()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hire scouts to edge into fog near Home and claimed sectors while you’re away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Label("\(state.hiredScouts.count) hired", systemImage: "person.fill")
                Label(
                    "\(state.scoutDiscoveriesToday)/\(IdleConstants.dailyScoutDiscoveryCap) today",
                    systemImage: "sparkles"
                )
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AtlasTheme.teal)
        }
    }

    private var scoutStanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scout stance")
                .font(.subheadline.weight(.semibold))
            Text(controller.scoutStance.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ScoutStance.allCases, id: \.self) { stance in
                        Button {
                            controller.setScoutStance(stance)
                        } label: {
                            Text(stance.title)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    stance == controller.scoutStance ? AtlasTheme.teal.opacity(0.2) : Color.secondary.opacity(0.1),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func lastWatchCard(_ report: IdleAdvanceReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last watch")
                .font(.subheadline.weight(.semibold))
            Text(IdleWatchCopy.summaryLine(for: report))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.homeDripItems.isEmpty {
                IdleWatchItemList(items: report.homeDripItems)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AtlasTheme.teal.opacity(0.10))
        }
    }

    private func scoutRow(_ scout: ScoutDefinition) -> some View {
        let hired = state.isHired(scout.id)
        let unlocked = state.isUnlocked(scout.id)
        let hireCheck = IdleScoutEngine().canHire(
            scoutID: scout.id,
            state: state,
            explorerLevel: controller.explorerLevel,
            availableQuantity: { controller.inventoryStore.quantity(of: $0) }
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: scout.symbolName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hired ? AtlasTheme.teal : (unlocked ? AtlasTheme.blue : .secondary))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(scout.name)
                        .font(.subheadline.weight(.semibold))
                    Text(scout.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text("\(scout.tilesPerHour)/h")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if hired {
                Label("On roster", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.teal)
            } else if !unlocked {
                Text(lockDetail(for: scout))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    costRow(scout.hireCost)
                    Button {
                        _ = controller.hireScout(scout.id)
                    } label: {
                        Text(hireButtonTitle(hireCheck))
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.teal)
                    .disabled({
                        if case .hired = hireCheck { return false }
                        return true
                    }())
                    .accessibilityIdentifier("hireScout_\(scout.id)")
                }
            }
        }
        .padding(12)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }

    private func lockDetail(for scout: ScoutDefinition) -> String {
        if let prerequisite = scout.prerequisiteScoutID,
           let name = ScoutCatalog.byID[prerequisite]?.name {
            return "Unlocks after hiring \(name)."
        }
        return "Locked."
    }

    private func hireButtonTitle(_ result: ScoutHireResult) -> String {
        switch result {
        case .hired:
            return "Hire scout"
        case .denied(let reason):
            return reason
        }
    }

    private func costRow(_ amounts: [ItemAmount]) -> some View {
        FlowWrap(spacing: 6) {
            ForEach(amounts) { amount in
                let name = ItemCatalog.definition(for: amount.itemID)?.name ?? amount.itemID
                let owned = controller.inventoryStore.quantity(of: amount.itemID)
                Text("\(amount.quantity)× \(name)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(owned >= amount.quantity ? AtlasTheme.teal.opacity(0.14) : AtlasTheme.finishRed.opacity(0.12))
                    )
            }
        }
    }
}

/// Reopen callout when Home Camp / scouts gathered something while away.
struct IdleWatchReportSheet: View {
    let summary: IdleWatchSummary
    let onDismiss: () -> Void

    private var report: IdleAdvanceReport { summary.report }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            Image(systemName: "person.3.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AtlasTheme.teal)
                .frame(width: 72, height: 72)
                .background(AtlasTheme.teal.opacity(0.14), in: Circle())

            Text("While you were away")
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("idleWatchReportTitle")

            Text(IdleWatchCopy.summaryLine(for: report))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if report.scoutDiscoveriesGranted > 0 {
                Label(
                    "\(report.scoutDiscoveriesGranted) scout tile\(report.scoutDiscoveriesGranted == 1 ? "" : "s") uncovered",
                    systemImage: "sparkles"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AtlasTheme.teal)
            }

            if !report.homeDripItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Camp goods")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    IdleWatchItemList(items: report.homeDripItems)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            }

            Text(
                "AFK discoveries today \(summary.scoutDiscoveriesToday)/\(IdleConstants.dailyScoutDiscoveryCap)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button("Got it", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(AtlasTheme.teal)
                .padding(.bottom, 24)
                .accessibilityIdentifier("idleWatchReportDismiss")
        }
        .padding()
        .accessibilityIdentifier("idleWatchReportSheet")
    }
}

enum IdleWatchCopy {
    static func summaryLine(for report: IdleAdvanceReport) -> String {
        let campGoods = report.homeDripItems.reduce(0) { $0 + $1.quantity }
        return "\(report.simulatedMinutes) min simulated · \(report.scoutDiscoveriesGranted) tiles · \(campGoods) camp goods"
    }
}

struct IdleWatchItemList: View {
    let items: [ItemAmount]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { amount in
                let definition = ItemCatalog.definition(for: amount.itemID)
                HStack(spacing: 8) {
                    Image(systemName: definition?.symbolName ?? "shippingbox")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.teal)
                        .frame(width: 18)
                    Text(definition?.name ?? amount.itemID)
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Text("×\(amount.quantity)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Simple wrapping layout for hire-cost chips without pulling in extra dependencies.
private struct FlowWrap<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // LazyVGrid keeps chip rows compact on phone widths.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: spacing)],
            alignment: .leading,
            spacing: spacing
        ) {
            content()
        }
    }
}
