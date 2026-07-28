import SwiftUI

/// First-run walkthrough explaining the three core game loops.
struct OnboardingOverlay: View {
    @Binding var step: Int
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [(icon: String, title: String, body: String)] = [
        (
            "hexagon.fill",
            "Discover your atlas",
            "Start an activity and move through the world. New hex tiles are revealed as you go — revisits build familiarity XP and mastery."
        ),
        (
            "flag.2.crossed.fill",
            "Frontier expeditions",
            "Each week, pick a mission on the map. Push into new sectors, chain combos, and climb the weekly leaderboard."
        ),
        (
            "sparkles",
            "World events & hotspots",
            "Daily hotspots mark things to chase nearby. Time-limited world events boost XP, charge the frontier, or send you on a beacon rush."
        ),
        (
            "scope",
            "Play Pinpoint",
            "Guess where you are from Apple Look Around. Worldwide mode is always open; Home Turf unlocks as you discover tiles nearby."
        )
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: steps[step].icon)
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AtlasTheme.blue, AtlasTheme.teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .id("icon-\(step)")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))

                    Text(steps[step].title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .id("title-\(step)")
                        .transition(.opacity.combined(with: .offset(y: 8)))

                    Text(steps[step].body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("body-\(step)")
                        .transition(.opacity)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background {
                    GlassChrome(
                        shape: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous),
                        weight: .regular
                    )
                }
                .padding(.horizontal, 24)
                .animation(AtlasMotion.optional(AtlasMotion.chrome, reduceMotion: reduceMotion), value: step)

                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? AtlasTheme.blue : Color.secondary.opacity(0.3))
                            .frame(width: index == step ? 20 : 8, height: 8)
                            .animation(AtlasMotion.optional(AtlasMotion.fade, reduceMotion: reduceMotion), value: step)
                    }
                }

                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") {
                            AtlasHaptics.select()
                            AtlasMotion.withOptionalAnimation(AtlasMotion.chrome, reduceMotion: reduceMotion) {
                                step -= 1
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(step == steps.count - 1 ? "Get started" : "Next") {
                        if step == steps.count - 1 {
                            AtlasHaptics.success()
                            onComplete()
                        } else {
                            AtlasHaptics.select()
                            AtlasMotion.withOptionalAnimation(AtlasMotion.chrome, reduceMotion: reduceMotion) {
                                step += 1
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.blue)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("onboardingOverlay")
    }
}
