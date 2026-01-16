import SwiftUI

struct ContentHeaderRow<Trailing: View>: View {
    let iconName: String
    let title: String
    let subtitle: String?
    let titleLineLimit: Int
    let subtitleLineLimit: Int
    let alignment: VerticalAlignment
    let titleSubtitleAlignment: VerticalAlignment
    let trailing: Trailing

    init(
        iconName: String,
        title: String,
        subtitle: String? = nil,
        titleLineLimit: Int = 2,
        subtitleLineLimit: Int = 2,
        alignment: VerticalAlignment = .center,
        titleSubtitleAlignment: VerticalAlignment = .center,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.titleLineLimit = titleLineLimit
        self.subtitleLineLimit = subtitleLineLimit
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
                    .layoutPriority(1)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(subtitleLineLimit)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer()
            trailing
        }
    }
}
