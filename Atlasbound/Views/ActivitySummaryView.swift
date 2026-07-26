import SwiftUI

struct ActivitySummaryView: View {
    let summary: ActivitySummary
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    HStack(spacing: 0) {
                        summaryStat(title: "Distance", value: formatDistance(summary.distanceMeters))
                        summaryStat(title: "Duration", value: formatDuration(summary.duration))
                        summaryStat(title: "New tiles", value: "\(summary.tilesDiscovered)")
                    }
                    .padding(.vertical, 8)
                    .background(card)

                    VStack(spacing: 12) {
                        row("Visited tiles", "\(summary.tilesVisited)")
                        row("Revisited", "\(max(0, summary.tilesVisited - summary.tilesDiscovered))")
                        row("Discovery XP", "+\(summary.discoveryXP)")
                        row("Familiarity XP", "+\(summary.familiarityXP)")
                    }
                    .padding(16)
                    .background(card)

                    Text("New tiles provide discovery. Existing tiles provide mastery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(AtlasTheme.canvas(for: colorScheme).ignoresSafeArea())
            .navigationTitle("Activity Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(AtlasTheme.blue.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: summary.activityType.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AtlasTheme.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.activityType.activeTitle)
                    .font(.title3.weight(.bold))
                Text("+\(summary.totalXP) XP earned")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AtlasTheme.teal)
            }
            Spacer()
        }
        .padding(16)
        .background(card)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
            .fill(AtlasTheme.chromeFill(for: colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                    .strokeBorder(AtlasTheme.chromeStroke(for: colorScheme), lineWidth: 1)
            }
            .shadow(color: AtlasTheme.cardShadow(for: colorScheme), radius: 10, y: 3)
    }

    private func summaryStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }
}
