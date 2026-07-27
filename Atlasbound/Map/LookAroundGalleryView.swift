import SwiftUI
import UIKit

/// Spoiler-free Look Around gallery: static MapKit snapshots only (no live viewer).
struct LookAroundGalleryView: View {
    let images: [UIImage]

    @State private var selectedIndex = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if images.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                                .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .ignoresSafeArea()
                }

                appleMapsAttribution
            }
        }
    }

    private var appleMapsAttribution: some View {
        Text("Apple Maps")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 12)
            .padding(.bottom, 56)
            .allowsHitTesting(false)
    }
}
