import SwiftUI

/// Chooses the activity that drives reveal width and session stamps.
struct ActivityPickerSheet: View {
    @ObservedObject var controller: WorldController
    var startsTrackingOnSelection = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ActivityType.selectableCases, id: \.self) { type in
                        Button {
                            controller.setActivityType(type)
                            if startsTrackingOnSelection {
                                controller.startActivity()
                            }
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
                    Text("Activity tracking is optional. Every activity explores the same 20 m atlas and adds its type to your Journal history.")
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
                Text("Optional tracking · shared 20 m atlas")
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
