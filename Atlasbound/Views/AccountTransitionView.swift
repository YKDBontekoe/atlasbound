import SwiftUI

struct AccountTransitionView: View {
    let chooseCloud: () -> Void
    let chooseDevice: () -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.48).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(AtlasTheme.blue)
                Text("Choose your atlas")
                    .font(.title2.bold())
                Text("This account already has progress. Choose which atlas should be kept on this device and in the cloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Use cloud atlas", action: chooseCloud)
                    .buttonStyle(.borderedProminent)
                    .tint(AtlasTheme.blue)
                    .frame(maxWidth: .infinity)
                Button("Keep this device’s atlas", action: chooseDevice)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Cancel sign-in", role: .cancel, action: cancel)
                    .font(.footnote)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(24)
        }
        .accessibilityIdentifier("accountTransitionView")
    }
}
