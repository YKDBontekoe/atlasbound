import SwiftUI

/// Full-screen preparing experience while Pinpoint scouts Look Around drops.
struct PinpointPreparingView: View {
    @ObservedObject var controller: PinpointController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettledMotion

    @State private var statusIndex = 0
    @State private var pulse = false

    private let statusLines = [
        "Probing Look Around coverage…",
        "Checking mapped streets…",
        "Finding your next drop…",
        "Scanning ordinary neighborhoods…",
        "Locking in distant rounds…"
    ]

    private var settleMotion: Bool {
        reduceMotion || forceSettledMotion
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                mark
                    .staggeredAppear(index: 0)

                VStack(spacing: 10) {
                    Text("Scouting locations")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text(controller.currentMode.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(modeTint)
                    Text(statusLines[statusIndex % statusLines.count])
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .animation(AtlasMotion.optional(AtlasMotion.fade, reduceMotion: settleMotion), value: statusIndex)
                        .frame(maxWidth: 280)
                        .id(statusIndex)
                }
                .staggeredAppear(index: 1)

                progressSection
                    .staggeredAppear(index: 2)

                Spacer()

                Button("Cancel") {
                    AtlasHaptics.select()
                    controller.cancelPreparation()
                }
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .buttonStyle(GlassButtonStyle(shape: .capsule))
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
                .staggeredAppear(index: 3)
            }
        }
        .onAppear {
            guard !settleMotion else { return }
            withAnimation(AtlasMotion.ambient.repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .task(id: controller.phase) {
            guard controller.phase == .preparing, !settleMotion else { return }
            while !Task.isCancelled, controller.phase == .preparing {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, controller.phase == .preparing else { return }
                statusIndex = (statusIndex + 1) % statusLines.count
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scouting Pinpoint locations")
        .accessibilityValue("Found \(controller.preparationFoundCount) of \(controller.preparationTargetCount)")
    }

    private var modeTint: Color {
        controller.currentMode == .homeTurf ? AtlasTheme.gold : AtlasTheme.blue
    }

    private var background: some View {
        LinearGradient(
            colors: [
                modeTint.opacity(0.42),
                AtlasTheme.teal.opacity(0.28),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    AtlasTheme.gold.opacity(0.18),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 320
            )
        }
    }

    private var mark: some View {
        ZStack {
            Circle()
                .fill(modeTint.opacity(pulse ? 0.22 : 0.12))
                .frame(width: pulse ? 148 : 128, height: pulse ? 148 : 128)

            ZStack {
                Image(systemName: "hexagon.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [modeTint, AtlasTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "scope")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }
            .shadow(color: modeTint.opacity(0.35), radius: 16, y: 6)
        }
        .frame(height: 160)
    }

    private var progressSection: some View {
        VStack(spacing: 14) {
            Text("Found \(controller.preparationFoundCount) of \(controller.preparationTargetCount)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(AtlasMotion.optional(AtlasMotion.number, reduceMotion: settleMotion), value: controller.preparationFoundCount)

            HStack(spacing: 10) {
                ForEach(0..<controller.preparationTargetCount, id: \.self) { index in
                    Capsule()
                        .fill(index < controller.preparationFoundCount ? modeTint : Color.primary.opacity(0.12))
                        .frame(width: 36, height: 8)
                        .animation(AtlasMotion.optional(AtlasMotion.chrome, reduceMotion: settleMotion), value: controller.preparationFoundCount)
                }
            }

            ProgressView(value: Double(controller.preparationFoundCount), total: Double(max(controller.preparationTargetCount, 1)))
                .tint(modeTint)
                .frame(maxWidth: 220)
        }
        .padding(20)
        .background {
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                weight: .regular
            )
        }
        .padding(.horizontal, 28)
    }
}
