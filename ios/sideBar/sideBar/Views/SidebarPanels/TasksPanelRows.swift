import SwiftUI

struct TaskPanelRow: View, Equatable {
    let title: String
    let iconName: String
    let count: Int?
    let isSelected: Bool
    let indent: CGFloat
    let useListStyling: Bool

    init(
        title: String,
        iconName: String,
        count: Int? = nil,
        isSelected: Bool = false,
        indent: CGFloat = 0,
        useListStyling: Bool = true
    ) {
        self.title = title
        self.iconName = iconName
        self.count = count
        self.isSelected = isSelected
        self.indent = indent
        self.useListStyling = useListStyling
    }

    static func == (lhs: TaskPanelRow, rhs: TaskPanelRow) -> Bool {
        lhs.title == rhs.title &&
        lhs.iconName == rhs.iconName &&
        lhs.count == rhs.count &&
        lhs.isSelected == rhs.isSelected &&
        lhs.indent == rhs.indent &&
        lhs.useListStyling == rhs.useListStyling
    }

    var body: some View {
        SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            useListStyling: useListStyling
        ) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(isSelected ? selectedTextColor : secondaryTextColor)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    .lineLimit(1)
                Spacer()
                if let count {
                    if count == 0 {
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                            .accessibilityLabel("No tasks")
                    } else {
                        Text("\(count)")
                            .font(.caption)
                            .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                    }
                }
            }
        }
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
        horizontalPadding = DesignTokens.Spacing.xs + indent
        #else
        horizontalPadding = DesignTokens.Spacing.sm + indent
        #endif
        return EdgeInsets(
            top: 0,
            leading: horizontalPadding,
            bottom: 0,
            trailing: DesignTokens.Spacing.sm
        )
    }
}
