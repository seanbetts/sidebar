import SwiftUI
import WidgetKit

struct WidgetHeaderView: View {
    let title: String
    let totalCount: Int
    let destination: URL
    let reduceTitleForSmall: Bool
    let family: WidgetFamily

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                Image("AppLogo")
                    .resizable()
                    .widgetAccentedRenderingMode(.accentedDesaturated)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                Text(title)
                    .font(titleFont)
                    .fontWeight(.semibold)
                Spacer()
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .widgetAccentable()
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var isSmall: Bool {
        family == .systemSmall
    }

    private var iconSize: CGFloat {
        18
    }

    private var titleFont: Font {
        if isSmall && reduceTitleForSmall {
            return .subheadline
        }
        return .headline
    }
}

struct WidgetListLayout<Header: View, List: View, Footer: View>: View {
    let header: Header
    let list: List
    let footer: Footer?
    let family: WidgetFamily

    init(
        family: WidgetFamily,
        @ViewBuilder header: () -> Header,
        @ViewBuilder list: () -> List,
        @ViewBuilder footer: () -> Footer? = { nil }
    ) {
        self.family = family
        self.header = header()
        self.list = list()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            list
            if family != .systemSmall {
                Spacer(minLength: 0)
            }
            if let footer {
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
