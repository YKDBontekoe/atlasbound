import SwiftUI

struct ActivitySummaryView: View {
    let summary: ActivitySummary
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Activity", value: summary.activityType.rawValue.capitalized)
                    LabeledContent("Duration", value: formatDuration(summary.duration))
                    LabeledContent("Distance", value: formatDistance(summary.distanceMeters))
                    LabeledContent("GPS samples", value: "\(summary.sampleCount)")
                }

                Section("Tiles") {
                    LabeledContent("Visited", value: "\(summary.tilesVisited)")
                    LabeledContent("Newly discovered", value: "\(summary.tilesDiscovered)")
                    LabeledContent(
                        "Revisited",
                        value: "\(max(0, summary.tilesVisited - summary.tilesDiscovered))"
                    )
                }

                Section("XP") {
                    LabeledContent("Discovery XP", value: "+\(summary.discoveryXP)")
                    LabeledContent("Familiarity XP", value: "+\(summary.familiarityXP)")
                    LabeledContent("Total", value: "+\(summary.totalXP)")
                }

                Section {
                    Text("First visit discovers a tile and lifts fog permanently. Revisiting the same tiles awards diminishing familiarity XP instead of more discovery XP.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: interval) ?? "—"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
