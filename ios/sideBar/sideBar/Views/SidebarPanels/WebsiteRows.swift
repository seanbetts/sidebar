import Foundation
import SwiftUI

struct PendingWebsiteRow: View, Equatable {
    let pending: WebsitesViewModel.PendingWebsiteItem
    let useListStyling: Bool

    var body: some View {
        SelectableRow(
            isSelected: false,
            insets: rowInsets,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.75)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.title)
                        .font(.subheadline)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                    Text(formatDomain(pending.domain))
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
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
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = DesignTokens.Spacing.sm
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
    private let titleText: String
    private let subtitleText: String

    init(
        item: WebsiteItem,
        isSelected: Bool,
        useListStyling: Bool = true,
        faviconBaseUrl: URL? = nil,
        r2FaviconBucket: String? = nil,
        r2FaviconPublicBaseUrl: URL? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.useListStyling = useListStyling
        self.faviconBaseUrl = faviconBaseUrl
        self.r2FaviconBucket = r2FaviconBucket
        self.r2FaviconPublicBaseUrl = r2FaviconPublicBaseUrl
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
            useListStyling: useListStyling
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
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                        .lineLimit(1)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private static func formatSubtitle(domain: String, readingTime: String?) -> String {
        let cleanDomain = domain.replacingOccurrences(
            of: "^www\\.",
            with: "",
            options: .regularExpression
        )
        if let readingTime = readingTime, !readingTime.isEmpty {
            return "\(cleanDomain) | \(readingTime)"
        }
        return cleanDomain
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
        horizontalPadding = DesignTokens.Spacing.xs
        #else
        horizontalPadding = DesignTokens.Spacing.sm
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: horizontalPadding
        )
    }
}
