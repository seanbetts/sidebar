import SwiftUI

struct MetadataPill<LeadingAccessory: View>: View {
    let title: String
    private let leadingAccessory: LeadingAccessory
    private let showsLeadingAccessory: Bool

    init(
        _ title: String,
        @ViewBuilder leadingAccessory: () -> LeadingAccessory
    ) {
        self.title = title
        self.leadingAccessory = leadingAccessory()
        self.showsLeadingAccessory = true
    }

    init(_ title: String) where LeadingAccessory == EmptyView {
        self.title = title
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
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .glassChrome(.metadataPill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}
