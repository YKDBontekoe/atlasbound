#if DEBUG
import SwiftUI
import CoreLocation

/// In-app Simulator / DEBUG controls for walking the hex grid without Xcode GPX menus.
struct DebugLocationPad: View {
    @ObservedObject var controller: WorldController
    @ObservedObject private var recorder: ActivityRecorder

    @Binding var followsUser: Bool

    @State private var step: WorldController.DebugStepSize = .tile
    @State private var headingDegrees: Double = 0
    @State private var autoWalk = false
    @State private var expanded = true

    init(controller: WorldController, followsUser: Binding<Bool>) {
        self.controller = controller
        self._recorder = ObservedObject(wrappedValue: controller.recorder)
        self._followsUser = followsUser
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if expanded, recorder.isSimulationActive {
                controls
            }
        }
        .padding(12)
        .frame(maxWidth: 220, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .onDisappear { stopAutoWalk() }
        .onChange(of: autoWalk) { _, walking in
            if walking { startAutoWalk() } else { stopAutoWalk() }
        }
        .onChange(of: recorder.isSimulationActive) { _, active in
            if !active { stopAutoWalk(); autoWalk = false }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.north.line.fill")
                .foregroundStyle(AtlasTheme.blue)
            Text("Sim GPS")
                .font(.caption.weight(.bold))
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { recorder.isSimulationActive },
                set: { enabled in
                    if enabled {
                        controller.debugEnableSimulation(seedIfNeeded: true)
                        followsUser = true
                    } else {
                        stopAutoWalk()
                        autoWalk = false
                        controller.debugDisableSimulation()
                    }
                }
            ))
            .labelsHidden()
            .tint(AtlasTheme.teal)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Step", selection: $step) {
                ForEach(WorldController.DebugStepSize.allCases) { size in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)

            dPad

            HStack(spacing: 8) {
                Button {
                    controller.debugTeleport(to: WorldController.debugDefaultCoordinate)
                    followsUser = true
                    headingDegrees = 0
                } label: {
                    Label("Dordrecht", systemImage: "mappin.and.ellipse")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Toggle(isOn: $autoWalk) {
                    Text("Auto")
                        .font(.caption2.weight(.semibold))
                }
                .toggleStyle(.button)
                .tint(AtlasTheme.teal)
            }

            Text("Start Activity, then nudge — tiles reveal via the same path as GPS.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dPad: some View {
        VStack(spacing: 6) {
            nudgeButton(systemName: "arrow.up", heading: 0)
            HStack(spacing: 6) {
                nudgeButton(systemName: "arrow.left", heading: 270)
                Button {
                    // Stay put but refresh sample (useful mid-session).
                    if let coordinate = recorder.lastLocation?.coordinate {
                        controller.debugTeleport(to: coordinate, course: headingDegrees, speed: 0)
                    }
                } label: {
                    Image(systemName: "dot.scope")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.85), in: Circle())
                }
                .buttonStyle(.plain)
                nudgeButton(systemName: "arrow.right", heading: 90)
            }
            nudgeButton(systemName: "arrow.down", heading: 180)
        }
        .frame(maxWidth: .infinity)
    }

    private func nudgeButton(systemName: String, heading: Double) -> some View {
        Button {
            headingDegrees = heading
            followsUser = true
            controller.debugNudge(headingDegrees: heading, distanceMeters: step.rawValue, speed: speedForStep)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AtlasTheme.blue)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.92), in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    private var speedForStep: CLLocationSpeed {
        // Rough m/s so the live speed readout looks plausible.
        switch step {
        case .fine: return 1.2
        case .tile: return 1.6
        case .leap: return 4.0
        }
    }

    private func startAutoWalk() {
        stopAutoWalk()
        autoWalkTask = Task { @MainActor in
            while !Task.isCancelled, autoWalk, recorder.isSimulationActive {
                followsUser = true
                controller.debugNudge(
                    headingDegrees: headingDegrees,
                    distanceMeters: step.rawValue,
                    speed: speedForStep
                )
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
    }

    private func stopAutoWalk() {
        autoWalkTask?.cancel()
        autoWalkTask = nil
    }

    @State private var autoWalkTask: Task<Void, Never>?
}
#endif
