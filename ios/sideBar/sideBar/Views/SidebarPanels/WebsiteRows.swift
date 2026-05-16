import Foundation
import SwiftUI
import sideBarShared

struct PendingWebsiteRow: View, Equatable {
    let pending: WebsitesViewModel.PendingWebsiteItem
    let useListStyling: Bool
    let onRetry: (() -> Void)?
    let onRemove: (() -> Void)?

    static func == (lhs: PendingWebsiteRow, rhs: PendingWebsiteRow) -> Bool {
        lhs.pending == rhs.pending && lhs.useListStyling == rhs.useListStyling
    }

    var leadingIcon: AppIcon? {
        pending.status == .failed ? AppIcon.Content.websiteFallback : nil
    }

    var body: some View {
        SelectableRow(
            isSelected: false,
            insets: rowInsets,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                if let leadingIcon {
                    Image(appIcon: leadingIcon)
                        .appFont(.label)
                        .foregroundStyle(secondaryTextColor)
                } else {
                    LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayTitle)
                        .appFont(SidebarTypography.primary)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                    Text(pending.statusLabel)
                        .appFont(SidebarTypography.secondary)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 8) {
                    if pending.status == .failed, let onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Image(appIcon: AppIcon.State.retry)
                                .appFont(.label)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(secondaryTextColor)
                        .accessibilityLabel("Retry website save")
                    }
                    if let onRemove {
                        Button {
                            onRemove()
                        } label: {
                            Image(appIcon: AppIcon.Action.cancel)
                                .appFont(.label)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(secondaryTextColor)
                        .accessibilityLabel("Remove pending website")
                    }
                }
            }
        }
    }

    private var displayTitle: String {
        let domain = formatDomain(pending.domain)
        if !domain.isEmpty {
            return domain
        }
        return pending.url
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.sm
        #else
        horizontalPadding = DesignTokens.Spacing.smPlus
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}

struct WebsiteRow: View, Equatable {
    let item: WebsiteItem
    let isSelected: Bool
    let useListStyling: Bool
    let faviconBaseUrl: URL?
    let r2FaviconBucket: String?
    let r2FaviconPublicBaseUrl: URL?
    let onSelect: (() -> Void)?
    private let titleText: String
    private let subtitleText: String

    init(
        item: WebsiteItem,
        isSelected: Bool,
        useListStyling: Bool = true,
        faviconBaseUrl: URL? = nil,
        r2FaviconBucket: String? = nil,
        r2FaviconPublicBaseUrl: URL? = nil,
        onSelect: (() -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.useListStyling = useListStyling
        self.faviconBaseUrl = faviconBaseUrl
        self.r2FaviconBucket = r2FaviconBucket
        self.r2FaviconPublicBaseUrl = r2FaviconPublicBaseUrl
        self.onSelect = onSelect
        self.titleText = item.title.isEmpty ? item.url : item.title
        self.subtitleText = WebsiteRow.formatSubtitle(
            domain: item.domain,
            readingTime: item.readingTime
        )
    }

    static func == (lhs: WebsiteRow, rhs: WebsiteRow) -> Bool {
        lhs.isSelected == rhs.isSelected &&
        lhs.useListStyling == rhs.useListStyling &&
        lhs.item.id == rhs.item.id &&
        lhs.item.title == rhs.item.title &&
        lhs.item.url == rhs.item.url &&
        lhs.item.domain == rhs.item.domain &&
        lhs.item.pinned == rhs.item.pinned &&
        lhs.item.pinnedOrder == rhs.item.pinnedOrder &&
        lhs.item.archived == rhs.item.archived &&
        lhs.item.updatedAt == rhs.item.updatedAt &&
        lhs.item.faviconUrl == rhs.item.faviconUrl &&
        lhs.item.faviconR2Key == rhs.item.faviconR2Key &&
        lhs.item.readingTime == rhs.item.readingTime &&
        lhs.r2FaviconBucket == rhs.r2FaviconBucket &&
        lhs.r2FaviconPublicBaseUrl == rhs.r2FaviconPublicBaseUrl
    }

    var body: some View {
        SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            useListStyling: useListStyling,
            primaryAction: onSelect
        ) {
            HStack(spacing: 8) {
                FaviconImageView(
                    faviconUrl: item.faviconUrl,
                    faviconR2Key: item.faviconR2Key,
                    r2Endpoint: faviconBaseUrl,
                    r2FaviconBucket: r2FaviconBucket,
                    r2FaviconPublicBaseUrl: r2FaviconPublicBaseUrl,
                    size: 16,
                    placeholderTint: isSelected ? selectedTextColor : secondaryTextColor
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleText)
                        .appFont(SidebarTypography.primary)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                        .lineLimit(1)
                    Text(subtitleText)
                        .appFont(SidebarTypography.secondary)
                        .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .systemShareAnchor(id: SystemShareAnchorID.websitesSidebarRow(item.id))
    }

    private static func formatSubtitle(domain: String, readingTime: String?) -> String {
        let cleanDomain = extractBaseDomain(domain)
        if let readingTime = readingTime, !readingTime.isEmpty {
            return "\(cleanDomain) | \(readingTime)"
        }
        return cleanDomain
    }

    private static func extractBaseDomain(_ domain: String) -> String {
        // Remove www. prefix first
        let cleaned = domain.replacingOccurrences(
            of: "^www\\.",
            with: "",
            options: .regularExpression
        )
        // Split by dots and extract base domain
        let parts = cleaned.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return cleaned }
        // Check for two-part TLDs like .co.uk, .org.uk, .com.au
        let secondLevelPrefixes: Set<String> = ["co", "com", "org", "net", "gov", "edu", "ac", "or"]
        let last = parts[parts.count - 1]
        let secondLast = parts[parts.count - 2]
        // If second-to-last is a common prefix and last is a 2-letter country code
        if secondLevelPrefixes.contains(secondLast.lowercased()) && last.count == 2 {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    private var primaryTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var secondaryTextColor: Color {
        DesignTokens.Colors.textSecondary
    }

    private var selectedTextColor: Color {
        DesignTokens.Colors.textPrimary
    }

    private var selectedSecondaryText: Color {
        DesignTokens.Colors.textSecondary
    }

    private var rowInsets: EdgeInsets {
        let horizontalPadding: CGFloat
        #if os(macOS)
        horizontalPadding = DesignTokens.Spacing.sm
        #else
        horizontalPadding = DesignTokens.Spacing.smPlus
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}
