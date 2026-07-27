import SwiftUI

enum GlassMaterialWeight {
    case ultraThin
    case regular

    var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .regular: .regularMaterial
        }
    }
}

enum GlassButtonShape {
    case circle
    case capsule
    case rounded(CGFloat)
}

/// Liquid-glass surface for iOS 17+ (material + stroke + soft shadow).
struct GlassChrome<S: InsettableShape>: View {
    let shape: S
    var weight: GlassMaterialWeight = .ultraThin
    var tint: Color? = nil
    var tintOpacity: Double = 0.55

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        shape
            .fill(weight.material)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(tintOpacity))
                }
            }
            .overlay {
                shape.strokeBorder(strokeColor, lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: colorScheme == .dark ? 10 : 8,
                y: 3
            )
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.white.opacity(0.55)
    }
}

struct GlassButtonStyle: ButtonStyle {
    var shape: GlassButtonShape = .circle
    var weight: GlassMaterialWeight = .ultraThin

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { chrome }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(AtlasMotion.press, value: configuration.isPressed)
    }

    @ViewBuilder
    private var chrome: some View {
        switch shape {
        case .circle:
            GlassChrome(shape: Circle(), weight: weight)
        case .capsule:
            GlassChrome(shape: Capsule(), weight: weight)
        case .rounded(let radius):
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                weight: weight
            )
        }
    }
}

struct TintedGlassButtonStyle: ButtonStyle {
    var tint: Color
    var shape: GlassButtonShape = .capsule
    var weight: GlassMaterialWeight = .regular
    var tintOpacity: Double = 0.72

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background { chrome }
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AtlasMotion.press, value: configuration.isPressed)
    }

    @ViewBuilder
    private var chrome: some View {
        switch shape {
        case .circle:
            GlassChrome(shape: Circle(), weight: weight, tint: tint, tintOpacity: tintOpacity)
        case .capsule:
            GlassChrome(shape: Capsule(), weight: weight, tint: tint, tintOpacity: tintOpacity)
        case .rounded(let radius):
            GlassChrome(
                shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                weight: weight,
                tint: tint,
                tintOpacity: tintOpacity
            )
        }
    }
}
