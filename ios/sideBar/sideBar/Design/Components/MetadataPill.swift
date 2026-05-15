import SwiftUI

struct MetadataPill<LeadingAccessory: View>: View {
    let title: String
    let maxTitleWidth: CGFloat?
    private let leadingAccessory: LeadingAccessory
    private let showsLeadingAccessory: Bool

    init(
        _ title: String,
        maxTitleWidth: CGFloat? = nil,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory
    ) {
        self.title = title
        self.maxTitleWidth = maxTitleWidth
        self.leadingAccessory = leadingAccessory()
        self.showsLeadingAccessory = true
    }

    init(_ title: String, maxTitleWidth: CGFloat? = nil) where LeadingAccessory == EmptyView {
        self.title = title
        self.maxTitleWidth = maxTitleWidth
        self.leadingAccessory = EmptyView()
        self.showsLeadingAccessory = false
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxsPlus) {
            if showsLeadingAccessory {
                leadingAccessory
            }

            Text(title)
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: maxTitleWidth, alignment: .leading)
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .glassChrome(.metadataPill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
