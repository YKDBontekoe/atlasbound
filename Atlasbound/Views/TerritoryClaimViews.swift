import SwiftUI

/// Compact claim / Home Base CTA for the idle Adventures stack.
struct TerritoryClaimCard: View {
    @ObservedObject var controller: WorldController
    var onManageTap: () -> Void = {}

    private var presence: TerritoryPresenceSnapshot {
        controller.territoryPresence
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(AtlasTheme.homeBaseAccent.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: presence.isHomeBase ? "house.fill" : "flag.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AtlasTheme.homeBaseAccent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Territory")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(presence.playerSectorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(statusBadge)
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(statusTint)
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if presence.canClaim {
                    Button {
                        _ = controller.claimCurrentSector()
                    } label: {
                        Label("Claim sector", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.teal)
                    .accessibilityIdentifier("claimSectorButton")
                } else if presence.canSetHome {
                    Button {
                        _ = controller.setHomeBaseToCurrentSector()
                    } label: {
                        Label("Set Home Base", systemImage: "house.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.homeBaseAccent)
                    .accessibilityIdentifier("setHomeBaseButton")
                }

                if presence.claimCount > 0 || presence.canClaim {
                    Button(action: onManageTap) {
                        Image(systemName: "list.bullet")
                            .font(.caption.weight(.semibold))
                            .frame(width: 36, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("manageTerritoryButton")
                    .accessibilityLabel("Manage territory")
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
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("territoryClaimCard")
    }

    private var statusBadge: String {
        if presence.isHomeBase { return "Home" }
        if presence.isClaimed { return "Claimed" }
        return "\(presence.completionPercent)%"
    }

    private var statusTint: Color {
        if presence.isHomeBase { return AtlasTheme.homeBaseAccent }
        if presence.isClaimed { return AtlasTheme.teal }
        return presence.canClaim ? AtlasTheme.teal : .secondary
    }

    private var statusDetail: String {
        if presence.isHomeBase {
            return "Home Base — +25% familiarity XP and stronger field finds here."
        }
        if presence.isClaimed {
            return "Claimed sector — +15% familiarity XP and boosted finds."
        }
        if presence.canClaim {
            return "Explored enough to claim this neighborhood."
        }
        let needed = Int((TerritoryConstants.claimCompletionThreshold * 100).rounded())
        return "Discover \(needed)% of this sector to claim it (\(presence.completionPercent)% so far)."
    }
}

/// Sheet listing claimed sectors with Home Base controls.
struct TerritoryManageSheet: View {
    @ObservedObject var controller: WorldController
    @Environment(\.dismiss) private var dismiss

    private var state: TerritoryState { controller.territoryState }
    private var presence: TerritoryPresenceSnapshot { controller.territoryPresence }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if state.claims.isEmpty {
                        Text("No claimed sectors yet. Explore a neighborhood to 25% and claim it from the map.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.claims) { claim in
                            claimRow(claim)
                        }
                    }
                } header: {
                    Text("Claims")
                } footer: {
                    Text("Claims store sector IDs only. Soft XP and find buffs apply while you explore inside claimed sectors.")
                }

                if let sectorID = presence.playerSectorID {
                    Section("Here now") {
                        LabeledContent("Sector", value: presence.playerSectorName)
                        LabeledContent("Explored", value: "\(presence.completionPercent)%")
                        if presence.canClaim {
                            Button("Claim \(presence.playerSectorName)") {
                                _ = controller.claimSector(sectorID)
                            }
                        } else if presence.canSetHome {
                            Button("Make Home Base") {
                                _ = controller.setHomeBase(sectorID: sectorID)
                            }
                        } else if presence.isHomeBase {
                            Text("This is your Home Base.")
                                .foregroundStyle(.secondary)
                        } else if let ready = presence.homeMoveReadyAt, ready > .now {
                            Text("Home Base can move after \(ready.formatted(date: .omitted, time: .shortened)).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Territory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func claimRow(_ claim: TerritoryClaim) -> some View {
        let isHome = state.homeSectorID == claim.sectorID
        let name = controller.territoryDisplayName(forSectorID: claim.sectorID)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                Text(claim.claimedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isHome {
                Label("Home", systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.homeBaseAccent)
            } else if controller.canSetHomeBase(sectorID: claim.sectorID) {
                Button("Set home") {
                    _ = controller.setHomeBase(sectorID: claim.sectorID)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .accessibilityIdentifier("territoryClaimRow-\(claim.sectorID)")
    }
}
