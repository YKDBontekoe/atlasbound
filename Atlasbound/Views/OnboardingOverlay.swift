import SwiftUI

/// Versioned walkthrough explaining the exploration-first game loop.
struct OnboardingOverlay: View {
    @Binding var step: Int
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [(icon: String, title: String, body: String)] = [
        (
            "hexagon.fill",
            "Discover your atlas",
            "Move through the world to reveal new hex tiles automatically — no fitness activity is required."
        ),
        (
            "map.fill",
            "Follow treasure trails",
            "Chase three nearby landmark clues each day. Choose a quick route or a longer detour with better rare-relic odds."
        ),
        (
            "lock.open.fill",
            "Unlock the weekly vault",
            "Daily trails earn keys. Collect three to reveal a weekly vault and a guaranteed rare-or-better relic."
        ),
        (
            "location.fill",
            "Explore your way",
            "Exploration runs automatically while the app is open. You can optionally enable screen-locked exploration in Settings."
        )
    ]

    private var artName: String {
        ["FieldKitMark", "TreasureCacheMark", "PinpointMark", "FactoryMark"][step]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 16) {
                    AtlasArtMark(name: artName, size: 76)
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
