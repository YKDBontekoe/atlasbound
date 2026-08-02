import SwiftUI

// MARK: - AtlasLoadingStage

/// Full-screen branded loading stage (bootstrap and similar waits).
struct AtlasLoadingStage: View {
    let title: String
    var status: String = "Loading…"
    var artName: String? = "ExplorerMark"
    var systemImage: String = "hexagon.fill"
    var accent: Color = AtlasTheme.blue
    var accessibilityLabel: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled
    @State private var pulse = false
    @State private var appeared = false

    private var settleMotion: Bool {
        reduceMotion || forceSettled
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: AtlasTheme.Space.xxl) {
                Spacer(minLength: 0)

                mark
                    .opacity(appeared || settleMotion ? 1 : 0)
                    .scaleEffect(appeared || settleMotion ? 1 : 0.92)

                VStack(spacing: AtlasTheme.Space.sm) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                    Text(status)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(appeared || settleMotion ? 1 : 0)
                .offset(y: appeared || settleMotion ? 0 : 8)

                ProgressView()
                    .controlSize(.regular)
                    .tint(accent)
                    .opacity(appeared || settleMotion ? 1 : 0)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AtlasTheme.Space.xxl)
        }
        .onAppear {
            if settleMotion {
                appeared = true
                pulse = true
                return
            }
            withAnimation(AtlasMotion.chrome) {
                appeared = true
            }
            withAnimation(AtlasMotion.ambient.repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? "\(title). \(status)")
    }

    private var background: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.36),
                AtlasTheme.teal.opacity(0.22),
                Color(.systemBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [
                    AtlasTheme.gold.opacity(0.14),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 16,
                endRadius: 300
            )
        }
    }

    private var mark: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(pulse ? 0.20 : 0.10))
                .frame(width: pulse ? 132 : 116, height: pulse ? 132 : 116)

            if let artName {
                AtlasArtMark(name: artName, size: 88)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent, AtlasTheme.teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(height: 140)
    }
}

// MARK: - LoadingWorldView

/// App bootstrap splash used while controllers finish wiring.
struct LoadingWorldView: View {
    var body: some View {
        AtlasLoadingStage(
            title: "Atlasbound",
            status: "Loading world…",
            artName: "ExplorerMark",
            accent: AtlasTheme.blue,
            accessibilityLabel: "Loading Atlasbound"
        )
        .accessibilityIdentifier("loadingWorldView")
    }
}

// MARK: - AtlasInlineBusyLabel

/// Compact caption + spinner for in-card async work.
struct AtlasInlineBusyLabel: View {
    let text: String
    var tint: Color = AtlasTheme.blue

    var body: some View {
        HStack(spacing: AtlasTheme.Space.sm) {
            ProgressView()
                .controlSize(.small)
                .tint(tint)
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}
