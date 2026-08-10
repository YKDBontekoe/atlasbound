import SwiftUI

struct PulseWorldCard: View {
    @ObservedObject var controller: WorldController
    var onTap: (AtlasPulse) -> Void

    private var pulse: AtlasPulse? { controller.activePulses.first }

    var body: some View {
        Group {
            if let pulse {
                Button { onTap(pulse) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(AtlasTheme.gold.opacity(0.18))
                                .frame(width: 38, height: 38)
                            Image(systemName: pulse.kind.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AtlasTheme.gold)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("World now")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(pulse.kind.title)
                                .font(.subheadline.weight(.semibold))
                            Text("\(pulse.phase.displayName) · \(remainingLabel(for: pulse))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
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
                .accessibilityIdentifier("worldNowCard")
                .accessibilityLabel("World now, \(pulse.kind.title), \(pulse.phase.displayName)")
            }
        }
        .padding(.horizontal, 12)
    }

    private func remainingLabel(for pulse: AtlasPulse) -> String {
        let seconds = max(0, Int(pulse.expiresAt.timeIntervalSinceNow))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? "\(hours)h left" : "\(minutes)m left"
    }
}

struct PulseDetailSheet: View {
    @ObservedObject var controller: WorldController
    let pulse: AtlasPulse
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var alertsEnabled = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    Text(pulse.kind.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Choose what to do")
                            .font(.headline)
                        ForEach(PulseAction.allCases, id: \.self) { action in
                            actionButton(action)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if alertsEnabled {
                        Label("World alerts are on", systemImage: "bell.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AtlasTheme.teal)
                    } else {
                        Button {
                            Task {
                                alertsEnabled = await controller.enableWorldAlerts()
                            }
                        } label: {
                            Label("Alert me when this peaks", systemImage: "bell.badge")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .navigationTitle("World signal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                alertsEnabled = PulseNotificationCoordinator.shared.isEnabled
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: pulse.kind.symbolName)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(AtlasTheme.gold)
                .frame(width: 46, height: 46)
                .background(AtlasTheme.gold.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(pulse.kind.title)
                    .font(.title3.weight(.bold))
                Text("\(pulse.phase.displayName) · \(timeRemaining)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AtlasTheme.gold)
            }
        }
    }

    private var timeRemaining: String {
        let minutes = max(0, Int(pulse.expiresAt.timeIntervalSinceNow) / 60)
        return minutes >= 60 ? "\(minutes / 60)h remaining" : "\(minutes)m remaining"
    }

    private func actionButton(_ action: PulseAction) -> some View {
        Button {
            switch controller.resolvePulse(pulse.id, action: action) {
            case .completed:
                dismiss()
            case .denied(let message):
                errorMessage = message
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action == .observe ? "eye.fill" : action == .stabilize ? "wand.and.stars" : "shippingbox.fill")
                    .foregroundStyle(AtlasTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                    Text(action.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct WorldBriefingSheet: View {
    let briefing: WorldBriefing
    @ObservedObject var controller: WorldController
    var onFocusPulse: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(AtlasTheme.gold)
                Text("Since you were away")
                    .font(.title2.weight(.bold))
                Text(briefing.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !briefing.reports.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scout reports")
                            .font(.headline)
                        ForEach(briefing.reports) { report in
                            Label(report.detail, systemImage: "person.3.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let recommended = briefing.recommendedPulseID {
                    Button("See the nearby signal") {
                        onFocusPulse(recommended)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.teal)
                }
                Spacer()
            }
            .padding(22)
            .navigationTitle("World briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
