import SwiftUI

// MARK: - AtlasSectionHeader

/// Title + optional subtitle used at the top of journal / factory chrome cards.
struct AtlasSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var accent: Color = AtlasTheme.blue

    var body: some View {
        HStack(alignment: .top, spacing: AtlasTheme.Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(accent)
                    .frame(width: 28, height: 28)
                    .background(accent.opacity(0.12), in: Circle())
            }

            VStack(alignment: .leading, spacing: AtlasTheme.Space.xs) {
                Text(title)
                    .font(.headline)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AtlasEmptyState

/// Compact empty-state block for card interiors (not a full-screen `ContentUnavailableView`).
struct AtlasEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "sparkles"
    var artName: String? = nil
    var accent: Color = AtlasTheme.teal
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: AtlasTheme.Space.md) {
            if let artName {
                AtlasArtMark(name: artName, size: 64)
            } else {
                Image(systemName: systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 48, height: 48)
                    .background(accent.opacity(0.12), in: Circle())
            }

            VStack(spacing: AtlasTheme.Space.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let message, !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AtlasTheme.Space.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AtlasMetricRow

/// Labeled metric row for card interiors (replaces stock `LabeledContent` in polished tabs).
struct AtlasMetricRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: AtlasTheme.Space.md) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
            }
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: AtlasTheme.Space.sm)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AtlasChromeLinkRow

/// Navigation / action row that matches card chrome density.
struct AtlasChromeLinkRow: View {
    let title: String
    var systemImage: String
    var subtitle: String? = nil
    var accent: Color = AtlasTheme.blue
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: AtlasTheme.Space.md) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
