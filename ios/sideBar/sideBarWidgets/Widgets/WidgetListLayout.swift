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
    let listFooterSpacing: CGFloat

    init(
        family: WidgetFamily,
        listFooterSpacing: CGFloat = 0,
        @ViewBuilder header: () -> Header,
        @ViewBuilder list: () -> List,
        @ViewBuilder footer: () -> Footer? = { nil }
    ) {
        self.family = family
        self.header = header()
        self.list = list()
        self.footer = footer()
        self.listFooterSpacing = listFooterSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            contentGroup
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var contentGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            list
            if let footer {
                Spacer(minLength: 0)
                footer
                    .padding(.top, listFooterSpacing)
            }
        }
    }
}
