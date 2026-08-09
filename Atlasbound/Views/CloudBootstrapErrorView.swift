import SwiftUI

/// Recovery screen for a failed authenticated bootstrap. Keeping this state
/// visible makes transient network failures recoverable instead of leaving the
/// app on an indefinite loading screen.
struct CloudBootstrapErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            AtlasTheme.canvas(for: colorScheme)
                .ignoresSafeArea()

            VStack(spacing: AtlasTheme.Space.lg) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(AtlasTheme.blue)

                VStack(spacing: AtlasTheme.Space.sm) {
                    Text("Couldn’t sync your atlas")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Try again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.blue)
            }
            .padding(AtlasTheme.Space.xxl)
            .frame(maxWidth: 420)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cloudBootstrapErrorView")
    }

    @Environment(\.colorScheme) private var colorScheme
}
