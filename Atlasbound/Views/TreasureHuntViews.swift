import SwiftUI

struct TreasureAdventureCard: View {
    @ObservedObject var store: TreasureStore
    /// When false, renders as an inline row for card interiors (Journal) without nested glass.
    var usesGlassChrome: Bool = true
    /// Landmark search refining today’s trail destinations.
    var isPreparing: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AtlasTheme.Space.md) {
                AtlasArtMark(name: "TreasureCacheMark", size: usesGlassChrome ? 42 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.weeklyVault.isUnlocked ? "Weekly vault revealed" : "Today’s treasure trail")
                        .font(.subheadline.weight(.semibold))
                    if isPreparing {
                        AtlasInlineBusyLabel(text: "Scouting nearby landmarks…", tint: AtlasTheme.gold)
                    } else {
                        Text(store.currentTarget.map { "\($0.name) · \(store.trailProgressLabel)" } ?? "Move to prepare nearby clues")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(usesGlassChrome ? AtlasTheme.Space.md : 0)
            .contentShape(Rectangle())
            .animation(AtlasMotion.fade, value: isPreparing)
        }
        .buttonStyle(.plain)
        .background {
            if usesGlassChrome {
                GlassChrome(
                    shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                    weight: .regular
                )
            }
        }
        .accessibilityIdentifier("treasureAdventureCard")
        .accessibilityHint("Opens today’s treasure trail details and progress.")
    }
}

struct TreasureDetailSheet: View {
    @ObservedObject var controller: WorldController
    @ObservedObject var store: TreasureStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let target = store.currentTarget {
                    Section {
                        Label(target.name, systemImage: store.weeklyVault.isUnlocked ? "lock.open.fill" : "mappin.and.ellipse")
                            .font(.headline)
                        Text(target.clue)
                            .foregroundStyle(.secondary)
                        LabeledContent("Type", value: target.category)
                        if target.isFallback {
                            Label("Offline procedural destination", systemImage: "wifi.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(store.weeklyVault.isUnlocked ? "Weekly Vault" : "Current Clue")
                    }
                } else if controller.isPreparingTreasureTrail {
                    Section {
                        AtlasInlineBusyLabel(text: "Scouting nearby landmarks…", tint: AtlasTheme.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AtlasTheme.Space.sm)
                    }
                } else {
                    ContentUnavailableView(
                        "Trail complete",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Return tomorrow for a fresh trail.")
                    )
                }

                Section("Progress") {
                    if controller.isPreparingTreasureTrail {
                        HStack {
                            Text("Daily trail")
                            Spacer()
                            AtlasInlineBusyLabel(text: "Preparing…", tint: AtlasTheme.gold)
                        }
                    } else {
                        LabeledContent("Daily trail", value: store.trailProgressLabel)
                    }
                    LabeledContent(
                        "Vault keys",
                        value: "\(store.weeklyVault.keys)/\(TreasureConstants.keysRequiredForVault)"
                    )
                    if let trail = store.dailyTrail,
                       trail.freeRerollsRemaining > 0,
                       !trail.isCompleted {
                        Button("Reroll destination") {
                            controller.rerollTreasureTrail()
                            AtlasHaptics.select()
                        }
                        .disabled(controller.isPreparingTreasureTrail)
                    }
                }

                Section {
                    Text("Exploration runs automatically while the app is open. Reach the marked tile; your choice at each cache changes the next route and relic odds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Treasure Hunt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TreasureEncounterSheet: View {
    let encounter: TreasureEncounter
    let onChoose: (TreasureChoice) -> Void

    var body: some View {
        VStack(spacing: 20) {
            AtlasArtMark(name: "TreasureCacheMark", size: 94)
                .padding(.top, 24)
            VStack(spacing: 6) {
                Text(encounter.isVault ? "Vault discovered!" : "Cache discovered!")
                    .font(.title2.weight(.bold))
                Text(encounter.target.name)
                    .font(.headline)
                Text(encounter.isVault
                     ? "The lock responds to your atlas keys."
                     : "Choose how to continue the trail. You never lose earned progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ForEach(TreasureChoice.allCases) { choice in
                Button {
                    onChoose(choice)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: choice == .direct ? "arrow.forward.circle.fill" : "text.magnifyingglass")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.title).font(.headline)
                            Text(choice.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .accessibilityIdentifier("treasureEncounterSheet")
    }
}

struct RelicRewardSheet: View {
    let reward: TreasureReward
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AtlasArtMark(name: "RelicMark", size: 112)
            Text("Relic recovered")
                .font(.title2.weight(.bold))
            Text(reward.relic.name)
                .font(.headline)
            Text("\(reward.relic.rarity.displayName) · \(reward.relic.theme.displayName)")
                .foregroundStyle(.secondary)
            Text("+\(reward.familiarityXP) familiarity XP")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AtlasTheme.teal)
            if reward.grantedVaultKey {
                Label("Weekly vault key earned", systemImage: "key.fill")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer()
            Button("Continue exploring", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(AtlasTheme.blue)
                .padding(.bottom, 24)
        }
        .padding()
    }
}
