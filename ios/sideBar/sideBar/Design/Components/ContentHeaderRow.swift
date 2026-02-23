import SwiftUI

struct ContentHeaderRow<Trailing: View>: View {
    let icon: AnyView
    let title: String
    let subtitle: String?
    let titleStyle: AppFontStyle
    let titleWeight: Font.Weight
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
    let titleSubtitleAxis: Axis
    let onTitleTap: (() -> Void)?
    let trailing: Trailing

    init(
        iconName: String,
        title: String,
        subtitle: String? = nil,
        titleStyle: AppFontStyle = .headline,
        titleWeight: Font.Weight = .regular,
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
        titleSubtitleAxis: Axis = .horizontal,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon = AnyView(
            Image(systemName: iconName)
                .appFont(.titleLg)
                .foregroundStyle(.primary)
        )
        self.title = title
        self.subtitle = subtitle
        self.titleStyle = titleStyle
        self.titleWeight = titleWeight
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
        self.titleSubtitleAxis = titleSubtitleAxis
        self.onTitleTap = onTitleTap
        self.trailing = trailing()
    }

    init(
        iconView: AnyView,
        title: String,
        subtitle: String? = nil,
        titleStyle: AppFontStyle = .headline,
        titleWeight: Font.Weight = .regular,
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
        titleSubtitleAxis: Axis = .horizontal,
        onTitleTap: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon = iconView
        self.title = title
        self.subtitle = subtitle
        self.titleStyle = titleStyle
        self.titleWeight = titleWeight
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
        self.titleSubtitleAxis = titleSubtitleAxis
        self.onTitleTap = onTitleTap
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: alignment, spacing: 12) {
            icon
            titleSubtitleContent
            Spacer()
            trailing
        }
    }

    @ViewBuilder
    private var titleSubtitleContent: some View {
        if titleSubtitleAxis == .vertical {
            VStack(alignment: .leading, spacing: 2) {
                titleView
                subtitleView
            }
        } else {
            HStack(alignment: titleSubtitleAlignment, spacing: 12) {
                titleView
                if let subtitle, !subtitle.isEmpty, subtitleShowsDivider {
                    Rectangle()
                        .fill(DesignTokens.Colors.border)
                        .frame(width: subtitleDividerWidth, height: subtitleDividerHeight)
                        .fixedSize()
                }
                subtitleView
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let onTitleTap {
            Button(action: onTitleTap) {
                Text(title)
                    .appFont(titleStyle)
                    .fontWeight(titleWeight)
                    .lineLimit(titleLineLimit)
                    .multilineTextAlignment(.leading)
                    .layoutPriority(titleLayoutPriority)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
        } else {
            Text(title)
                .appFont(titleStyle)
                .fontWeight(titleWeight)
                .lineLimit(titleLineLimit)
                .multilineTextAlignment(.leading)
                .layoutPriority(titleLayoutPriority)
                .truncationMode(.tail)
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(subtitleLineLimit)
                .multilineTextAlignment(.leading)
                .layoutPriority(subtitleLayoutPriority)
                .tracking(subtitleTracking)
        }
    }
}
