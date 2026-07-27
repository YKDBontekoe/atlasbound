import SwiftUI
import MapKit

/// Shows the result of a single Pinpoint round: map with target + guess, score, distance, tile badges.
struct PinpointRoundResultView: View {
    let result: PinpointRound
    let roundNumber: Int
    let totalRounds: Int
    let runningTotal: Int
    let onNext: () -> Void

    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition) {
                Marker("Target", systemImage: "mappin.circle.fill", coordinate: result.target)
                    .tint(AtlasTheme.teal)
                Marker("Your Guess", systemImage: "hand.point.up.fill", coordinate: result.guess)
                    .tint(AtlasTheme.finishRed)
                MapPolyline(coordinates: [result.target, result.guess])
                    .stroke(AtlasTheme.blue, lineWidth: 2)
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(maxHeight: .infinity)

            VStack(spacing: 16) {
                badgeRow

                HStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text("\(result.score)")
                            .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(scoreColor)
                        Text("points")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text(PinpointScoring.formatDistance(result.distanceMeters))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("distance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text("\(result.hexDistance)")
                            .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        Text("hex hops")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if result.familiarityXPAwarded > 0 {
                    Text("+\(result.familiarityXPAwarded) familiarity XP")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AtlasTheme.gold)
                }

                HStack {
                    Text("Round \(roundNumber + 1)/\(totalRounds)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Total: \(runningTotal)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                }

                Button {
                    onNext()
                } label: {
                    Text(roundNumber + 1 >= totalRounds ? "See Results" : "Next Round")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(TintedGlassButtonStyle(tint: AtlasTheme.blue, shape: .capsule))
            }
            .padding(20)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            let midLat = (result.target.latitude + result.guess.latitude) / 2
            let midLon = (result.target.longitude + result.guess.longitude) / 2
            let spanLat = abs(result.target.latitude - result.guess.latitude) * 1.5 + 0.5
            let spanLon = abs(result.target.longitude - result.guess.longitude) * 1.5 + 0.5
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: midLat, longitude: midLon),
                span: MKCoordinateSpan(latitudeDelta: max(spanLat, 1), longitudeDelta: max(spanLon, 1))
            ))
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            Text(result.mode.displayName)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AtlasTheme.blue.opacity(0.12), in: Capsule())

            if result.hitExactTile {
                badge("Exact tile", color: AtlasTheme.gold)
            } else if result.guessInDiscoveredAtlas {
                badge("Atlas hit", color: AtlasTheme.teal)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var scoreColor: Color {
        if result.score >= 4500 { return AtlasTheme.gold }
        if result.score >= 3000 { return AtlasTheme.teal }
        if result.score >= 1000 { return AtlasTheme.blue }
        return AtlasTheme.finishRed
    }
}
