import SwiftUI

// MARK: - AnimatedNumber

/// Integer counter with numeric content transition.
struct AnimatedNumber: View {
    let value: Int
    var font: Font = .system(.body, design: .rounded).weight(.bold)

    var body: some View {
        Text("\(value)")
            .font(font)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(AtlasMotion.number, value: value)
    }
}

// MARK: - StaggeredAppear

/// Opacity + slight Y offset entrance, optional index-based delay.
struct StaggeredAppear: ViewModifier {
    let index: Int
    var baseDelay: Double = 0.05
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion || forceSettled ? 1 : 0)
            .offset(y: visible || reduceMotion || forceSettled ? 0 : 10)
            .onAppear {
                guard !reduceMotion, !forceSettled else {
                    visible = true
                    return
                }
                withAnimation(AtlasMotion.chrome.delay(Double(index) * baseDelay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppear(index: index, baseDelay: baseDelay))
    }
}

// MARK: - CelebrateBadge

/// Scale + opacity pop for XP / mastery / exact-tile badges.
struct CelebrateBadge<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled
    @State private var popped = false
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(popped || reduceMotion || forceSettled ? 1 : 0.6)
            .opacity(popped || reduceMotion || forceSettled ? 1 : 0)
            .onAppear {
                guard !reduceMotion, !forceSettled else {
                    popped = true
                    return
                }
                withAnimation(AtlasMotion.celebrate) {
                    popped = true
                }
            }
    }
}

// MARK: - SessionFeedbackToast

/// Ephemeral capsule HUD for discovery / mastery feedback.
struct SessionFeedbackToast: View {
    let event: SessionFeedbackEvent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.bold))
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(event.subtitle)
                    .font(.caption2.weight(.medium))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : -14)
        .scaleEffect(visible ? 1 : 0.92)
        .onAppear {
            if reduceMotion {
                visible = true
                return
            }
            withAnimation(AtlasMotion.toastFade.delay(0.25)) {
                visible = false
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var iconName: String {
        switch event.kind {
        case .discovery: "hexagon.fill"
        case .mastery: "star.fill"
        case .worldEvent: "sparkles"
        case .hotspot: "circle.hexagongrid.fill"
        }
    }

    private var backgroundColor: Color {
        switch event.kind {
        case .discovery: AtlasTheme.teal
        case .mastery: AtlasTheme.gold
        case .worldEvent: AtlasTheme.eventAccent
        case .hotspot: AtlasTheme.eventAccent.opacity(0.92)
        }
    }
}

// MARK: - GrowOnAppear

/// Animates a 0→1 progress value for arcs and bars.
struct GrowOnAppear: ViewModifier {
    @Binding var progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled

    func body(content: Content) -> some View {
        content
            .onAppear {
                if reduceMotion || forceSettled {
                    progress = 1
                    return
                }
                progress = 0
                withAnimation(AtlasMotion.celebrate) {
                    progress = 1
                }
            }
    }
}

extension View {
    func growOnAppear(_ progress: Binding<Double>) -> some View {
        modifier(GrowOnAppear(progress: progress))
    }
}
