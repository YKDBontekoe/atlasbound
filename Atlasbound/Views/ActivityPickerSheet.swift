import SwiftUI

/// Chooses the activity that drives reveal width and session stamps.
struct ActivityPickerSheet: View {
    @ObservedObject var controller: WorldController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ActivityType.selectableCases, id: \.self) { type in
                        Button {
                            controller.setActivityType(type)
                            dismiss()
                        } label: {
                            ActivityTypeRow(
                                type: type,
                                isSelected: controller.recorder.activityType == type
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isRecording)
                    }
                } footer: {
                    Text("Reveal width follows your activity — narrow for walking and running, medium for cycling, hiking, and transit, wide for driving. Progress is stored per reveal grid.")
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("activityPickerClose")
                }
            }
        }
    }
}

struct ActivityTypeRow: View {
    let type: ActivityType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: type.symbolName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AtlasTheme.blue)
                .frame(width: 40, height: 40)
                .background(AtlasTheme.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(type.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(type.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(type.revealWidthLabel) · \(type.tileSize.label)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AtlasTheme.teal)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(AtlasTheme.blue)
                    .accessibilityLabel("Selected")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    ActivityPickerSheet(
        controller: WorldController(
            store: TileStore(),
            activityHistory: ActivityHistoryStore()
        )
    )
}
