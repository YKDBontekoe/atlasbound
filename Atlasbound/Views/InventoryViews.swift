import SwiftUI

struct FieldFindPickupSheet: View {
    let pickup: ItemPickup
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            AtlasArtMark(name: "FieldKitMark", size: 112)
            Text("Field find")
                .font(.title2.weight(.bold))
            Text(pickup.itemName)
                .font(.headline)
            Text("\(pickup.rarity.displayName) · ×\(pickup.find.quantity)")
                .foregroundStyle(.secondary)
            Text(pickup.find.isDiscoveryDrop ? "Recovered on a fresh tile" : "Recovered on a familiar path")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Stash it", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .tint(AtlasTheme.blue)
                .padding(.bottom, 24)
        }
        .padding()
        .accessibilityIdentifier("fieldFindPickupSheet")
    }
}

struct ActiveEffectChip: View {
    let effect: ActiveItemEffect

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ItemCatalog.definition(for: effect.itemID)?.symbolName ?? "sparkles")
                .font(.caption.weight(.bold))
            Text(effect.displayLabel)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(AtlasTheme.gold)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AtlasTheme.gold.opacity(0.14), in: Capsule())
        .accessibilityIdentifier("activeEffectChip")
    }
}

struct FieldFindMapMarkerView: View {
    let rarity: ItemRarity

    var body: some View {
        Image(systemName: "shippingbox.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(markerColor.gradient, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private var markerColor: Color {
        switch rarity {
        case .common: AtlasTheme.slate
        case .uncommon: AtlasTheme.teal
        case .rare: AtlasTheme.blue
        case .legendary: AtlasTheme.gold
        }
    }
}

struct InventoryItemRow: View {
    let stack: InventoryStack
    let onUse: () -> Void
    let onActivate: () -> Void
    let onSalvage: () -> Void
    let onDiscard: () -> Void

    private var definition: ItemDefinition? {
        ItemCatalog.definition(for: stack.itemID)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition?.symbolName ?? "questionmark.circle")
                .foregroundStyle(AtlasTheme.teal)
                .frame(width: 34, height: 34)
                .background(AtlasTheme.teal.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(definition?.name ?? stack.itemID)
                    .font(.subheadline.weight(.semibold))
                Text(definition?.detail ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("×\(stack.quantity)")
                    .font(.subheadline.weight(.bold))
                Text(definition?.rarity.displayName ?? "")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle((definition?.rarity ?? .common) >= .rare ? AtlasTheme.gold : .secondary)
            }
        }
        .contextMenu {
            if definition?.category == .boost || (definition?.category == .assembled && definition?.effectKind != .trailReroll && definition?.effectKind != .surveyBeacon) {
                Button("Use", action: onUse)
            }
            if definition?.category == .charge || definition?.effectKind == .trailReroll || definition?.effectKind == .surveyBeacon {
                Button("Activate", action: onActivate)
            }
            if definition?.canSalvage == true {
                Button("Salvage", action: onSalvage)
            }
            Button("Discard", role: .destructive, action: onDiscard)
        }
    }
}
