import SwiftUI
import Charts

// MARK: - StatKPI

struct StatKPI: View {
    let value: String
    let caption: String
    var accent: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .animation(AtlasMotion.number, value: value)
    }
}

// MARK: - StatSectionCard

struct StatSectionCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                    .fill(AtlasTheme.chromeFill(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous)
                            .strokeBorder(AtlasTheme.chromeStroke(for: colorScheme), lineWidth: 1)
                    }
                    .shadow(color: AtlasTheme.cardShadow(for: colorScheme), radius: 10, y: 3)
            }
    }
}

// MARK: - ActivityFootprintChart

struct ActivityFootprintChart: View {
    let entries: [StatsEngine.ActivityFootprintEntry]

    var body: some View {
        Chart(entries, id: \.activity) { entry in
            BarMark(
                x: .value("Tiles", entry.tileCount),
                y: .value("Footprint", "All")
            )
            .foregroundStyle(entry.activity.statsMapColor)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - SegmentedBar

struct SegmentedBar: View {
    let segments: [(color: Color, value: Double)]
    var height: CGFloat = 8
    var cornerRadius: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled
    @State private var growProgress: Double = 0

    private var total: Double {
        segments.reduce(0) { $0 + max(0, $1.value) }
    }

    private var progress: Double {
        (reduceMotion || forceSettled) ? 1 : growProgress
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let fraction = total > 0 ? max(0, seg.value) / total : 0
                    if fraction > 0 {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(seg.color)
                            .frame(width: max(3, fraction * progress * (geo.size.width - CGFloat(max(0, visibleCount - 1)) * 1.5)))
                    }
                }
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .growOnAppear($growProgress)
    }

    private var visibleCount: Int {
        segments.filter { $0.value > 0 }.count
    }
}

// MARK: - MasteryDistributionBar

struct MasteryDistributionBar: View {
    let counts: [(state: TileState, count: Int)]
    var height: CGFloat = 10

    var body: some View {
        SegmentedBar(
            segments: counts.map { (color: $0.state.mapStroke, value: Double($0.count)) },
            height: height
        )
    }
}

// MARK: - XPSplitArc

struct XPSplitArc: View {
    let discovery: Int
    let familiarity: Int
    var size: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.atlasForceSettledMotion) private var forceSettled
    @State private var growProgress: Double = 0

    private var total: Int { discovery + familiarity }
    private var discoveryFraction: Double {
        total > 0 ? Double(discovery) / Double(total) : 0.5
    }

    private var progress: Double {
        (reduceMotion || forceSettled) ? 1 : growProgress
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(AtlasTheme.slate.opacity(0.18), lineWidth: 6)

            Circle()
                .trim(from: 0, to: discoveryFraction * progress)
                .stroke(AtlasTheme.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: discoveryFraction * progress, to: progress)
                .stroke(AtlasTheme.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(total)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("XP")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .growOnAppear($growProgress)
    }
}

// MARK: - NerdStat

struct NerdStat: View {
    let label: String
    let value: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }
}

// MARK: - Formatters

enum StatsFormat {
    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let sessionTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func distance(_ meters: Double) -> String {
        "\(distanceValue(meters)) \(distanceUnit(meters))"
    }

    static func distanceValue(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f", meters / 1000)
        }
        return String(format: "%.0f", meters)
    }

    static func distanceUnit(_ meters: Double) -> String {
        meters >= 1000 ? "km" : "m"
    }

    /// Compact distance (1 decimal km).
    static func distanceCompact(_ meters: Double) -> String {
        meters >= 1000
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.0f m", meters)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Live session clock `HH:MM:SS`.
    static func clockDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    static func pace(_ meters: Double, duration: TimeInterval) -> String? {
        guard meters > 50, duration > 10 else { return nil }
        let km = meters / 1000
        let minPerKm = (duration / 60) / km
        if minPerKm < 100 {
            let whole = Int(minPerKm)
            let frac = Int((minPerKm - Double(whole)) * 60)
            return String(format: "%d'%02d\"/km", whole, frac)
        }
        return nil
    }

    static func rate(_ count: Int, duration: TimeInterval) -> String? {
        guard duration > 30 else { return nil }
        let perMin = Double(count) / (duration / 60)
        if perMin >= 1 {
            return String(format: "%.1f/min", perMin)
        }
        let perHour = perMin * 60
        return String(format: "%.1f/hr", perHour)
    }

    static func xpPerKm(_ xp: Int, meters: Double) -> String? {
        guard meters > 100 else { return nil }
        let km = meters / 1000
        let value = Double(xp) / km
        return String(format: "%.0f XP/km", value)
    }

    static func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return "0%" }
        let pct = Double(part) / Double(whole) * 100
        if pct >= 99.5 && part < whole { return "99%" }
        if pct < 1 && part > 0 { return "<1%" }
        return String(format: "%.0f%%", pct)
    }

    static func areaSquareKilometers(_ squareMeters: Double) -> String {
        let km2 = squareMeters / 1_000_000
        if km2 < 0.01 {
            return String(format: "%.0f m²", squareMeters)
        }
        if km2 < 1 {
            return String(format: "%.2f km²", km2)
        }
        return String(format: "%.1f km²", km2)
    }

    /// Playful comparison for unlocked territory.
    static func areaComparison(_ squareKilometers: Double) -> String? {
        guard squareKilometers > 0.001 else { return nil }
        let footballPitchKm2 = 0.00714
        let pitches = Int((squareKilometers / footballPitchKm2).rounded())
        if pitches >= 2 {
            return "≈ \(pitches) football pitches"
        }
        let cityBlockKm2 = 0.01
        if squareKilometers >= cityBlockKm2 * 0.5 {
            return "≈ \(max(1, Int((squareKilometers / cityBlockKm2).rounded()))) city blocks"
        }
        return nil
    }

    static func shortDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return shortDateFormatter.string(from: date)
    }

    static func sessionTimestamp(_ date: Date) -> String {
        sessionTimestampFormatter.string(from: date)
    }
}
