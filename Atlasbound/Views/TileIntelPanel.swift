import SwiftUI

/// Compact, movement-friendly inspector for the selected atlas hex.
struct TileIntelPanel: View {
    let tileID: String
    @ObservedObject var store: TileStore
    @ObservedObject var controller: WorldController
    @ObservedObject var factoryController: FactoryController
    let onDismiss: () -> Void

    private var tile: WorldTile? {
        store.tiles[tileID]
    }

    private var presentation: TileIntelPresentation {
        TileIntelPresentation(
            tileID: tileID,
            tile: tile,
            tileEngine: controller.tileEngine,
            playerLocation: controller.recorder.lastLocation,
            structures: factoryController.structures
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: tile?.state.markerSymbol ?? "hexagon.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(presentation.state.mapBrandColor)
                    .frame(width: 38, height: 38)
                    .background(presentation.state.mapBrandColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(presentation.state.displayName)
                            .font(.subheadline.weight(.bold))
                        if let distanceLabel = presentation.distanceLabel {
                            Text("· \(distanceLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let tile {
                        Text("\(tile.masteryXP) mastery XP · \(tile.visitCount) visits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Uncharted hex · move here to reveal it")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let structureName = presentation.structureName {
                        Label(structureName, systemImage: "gearshape.2.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AtlasTheme.gold)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(presentation.state.displayName) tile")
            .accessibilityValue(tile.map { "\($0.masteryXP) mastery XP, \($0.visitCount) visits" } ?? "Uncharted hex")

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tile intel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
    }
}
