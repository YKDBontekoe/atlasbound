import SwiftUI

/// A compact, map-first quest prompt derived from the active treasure landmark.
struct LandmarkQuestCard: View {
    let quest: LandmarkQuest
    let isVault: Bool
    let onFocus: () -> Void

    private var tint: Color {
        switch quest.theme {
        case .waterside: AtlasTheme.blue
        case .greenspace: AtlasTheme.teal
        case .heritage: AtlasTheme.gold
        case .city: AtlasTheme.legendaryAmber
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isVault ? "lock.open.fill" : quest.symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(isVault ? "Weekly vault" : quest.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(quest.target.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text("\(quest.distanceLabel) · \(quest.target.clue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button(action: onFocus) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Focus \(quest.target.name) on the map")
        }
        .padding(10)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Landmark quest: \(quest.title), \(quest.target.name), \(quest.distanceLabel)")
    }
}
