import SwiftUI

struct GuestWelcomeView: View {
    let startExploring: () -> Void
    let signIn: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AtlasTheme.canvas(for: colorScheme).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 32)
                    AtlasArtMark(name: "ExplorerMark", size: 96)
                    VStack(spacing: 10) {
                        Text("Your world is waiting")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Explore nearby places, reveal your atlas, and follow treasure trails at your own pace.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 420)

                    VStack(alignment: .leading, spacing: 16) {
                        welcomeRow("hexagon.fill", "Discover as you move", "Your nearby map unfolds into a personal 20 m atlas.")
                        welcomeRow("icloud.and.arrow.up", "Play locally first", "Your progress is saved on this device. Add an account later to sync it.")
                        welcomeRow("person.2.fill", "Join shared adventures", "Sign in when you want shared treasure and cross-device progress.")
                    }
                    .padding(20)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: 500)

                    VStack(spacing: 12) {
                        Button("Start exploring", action: startExploring)
                            .buttonStyle(.borderedProminent)
                            .tint(AtlasTheme.blue)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                        Button("I already have an account", action: signIn)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: 500)
                    Text("Location is requested only when you start exploring. You can change access any time in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 24)
            }
        }
        .accessibilityIdentifier("guestWelcomeView")
    }

    private func welcomeRow(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AtlasTheme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
