import SwiftUI
import WidgetKit
import sideBarShared

extension Image {
    init(appIcon: AppIcon) {
        self.init(systemName: appIcon.rawValue)
    }
}

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

enum HomeWidgetSignedOutContent {
    case tasks
    case notes
    case websites
    case files

    var subtitle: String {
        switch self {
        case .tasks:
            return "to see your tasks"
        case .notes:
            return "to see your notes"
        case .websites:
            return "to see your websites"
        case .files:
            return "to see your files"
        }
    }
}

struct HomeWidgetSignedOutView: View {
    let content: HomeWidgetSignedOutContent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            Image(appIcon: AppIcon.Settings.profileWarning)
                .font(.system(size: 32))
                .foregroundStyle(colorScheme == .dark ? .white : .black)
            Text("Sign in to sideBar")
                .font(.headline)
            Text(content.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HomeWidgetEmptyStateView: View {
    let icon: AppIcon
    let title: String
    let subtitle: String
    let destination: URL
    let accentIcon: Bool
    let trailingAccessory: AnyView?
    @Environment(\.colorScheme) private var colorScheme

    init(
        title: String,
        subtitle: String,
        icon: AppIcon,
        destination: URL,
        accentIcon: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.destination = destination
        self.accentIcon = accentIcon
        self.trailingAccessory = nil
    }

    init<TrailingAccessory: View>(
        title: String,
        subtitle: String,
        icon: AppIcon,
        destination: URL,
        accentIcon: Bool = true,
        @ViewBuilder trailingAccessory: () -> TrailingAccessory? = { nil }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.destination = destination
        self.accentIcon = accentIcon
        self.trailingAccessory = trailingAccessory().map { AnyView($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                iconView
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let trailingAccessory {
                HStack {
                    Spacer()
                    trailingAccessory
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 18)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(destination)
    }

    @ViewBuilder
    private var iconView: some View {
        let image = Image(appIcon: icon)
            .font(.system(size: 32))

        if accentIcon {
            image
                .foregroundStyle(.secondary)
                .widgetAccentable()
        } else {
            image
                .foregroundStyle(colorScheme == .dark ? .white : .black)
        }
    }
}

#if os(iOS)
struct LockScreenSignedOutRow: View {
    let icon: AppIcon

    var body: some View {
        HStack {
            Image(appIcon: icon)
            Text("Sign in to sideBar")
                .font(.caption)
        }
    }
}
#endif
