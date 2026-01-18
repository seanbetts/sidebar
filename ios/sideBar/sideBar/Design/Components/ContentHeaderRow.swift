import SwiftUI

struct ContentHeaderRow<Trailing: View>: View {
    let iconName: String
    let title: String
    let subtitle: String?
    let titleLineLimit: Int
    let subtitleLineLimit: Int
    let titleLayoutPriority: Double
    let subtitleLayoutPriority: Double
    let subtitleShowsDivider: Bool
    let subtitleDividerWidth: CGFloat
    let subtitleDividerHeight: CGFloat
    let subtitleTracking: CGFloat
    let alignment: VerticalAlignment
    let titleSubtitleAlignment: VerticalAlignment
    let trailing: Trailing

    init(
        iconName: String,
        title: String,
        subtitle: String? = nil,
        titleLineLimit: Int = 2,
        subtitleLineLimit: Int = 2,
        titleLayoutPriority: Double = 1,
        subtitleLayoutPriority: Double = 0,
        subtitleShowsDivider: Bool = false,
        subtitleDividerWidth: CGFloat = 2,
        subtitleDividerHeight: CGFloat = 20,
        subtitleTracking: CGFloat = 0,
        alignment: VerticalAlignment = .center,
        titleSubtitleAlignment: VerticalAlignment = .center,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
        self.titleLayoutPriority = titleLayoutPriority
        self.subtitleLayoutPriority = subtitleLayoutPriority
        self.subtitleShowsDivider = subtitleShowsDivider
        self.subtitleDividerWidth = subtitleDividerWidth
        self.subtitleDividerHeight = subtitleDividerHeight
        self.subtitleTracking = subtitleTracking
        self.alignment = alignment
        self.titleSubtitleAlignment = titleSubtitleAlignment
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            HStack(alignment: titleSubtitleAlignment, spacing: 12) {
                Text(title)
                    .font(.headline)
                    .lineLimit(titleLineLimit)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(titleLayoutPriority)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    if subtitleShowsDivider {
                        Rectangle()
                            .fill(DesignTokens.Colors.border)
                            .frame(width: subtitleDividerWidth, height: subtitleDividerHeight)
                            .fixedSize()
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .multilineTextAlignment(.leading)
                        .layoutPriority(subtitleLayoutPriority)
                        .tracking(subtitleTracking)
                }
            }
            Spacer()
            trailing
        }
    }
}
