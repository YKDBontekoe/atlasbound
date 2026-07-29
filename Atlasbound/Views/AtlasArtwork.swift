import SwiftUI

/// Small, transparent atlas illustrations that complement native SwiftUI chrome.
struct AtlasArtMark: View {
    let name: String
    var size: CGFloat = 56

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
