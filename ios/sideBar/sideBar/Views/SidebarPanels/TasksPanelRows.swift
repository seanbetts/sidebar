import SwiftUI
import sideBarShared

struct TaskPanelRow: View, Equatable {
    let title: String
    let iconName: String
    let count: Int?
    let isSelected: Bool
    let indent: CGFloat
    let useListStyling: Bool
    let primaryAction: (() -> Void)?
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?

    init(
        title: String,
        iconName: String,
        count: Int? = nil,
        isSelected: Bool = false,
        indent: CGFloat = 0,
        useListStyling: Bool = true,
        primaryAction: (() -> Void)? = nil,
        onRename: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.title = title
        self.iconName = iconName
        self.count = count
        self.isSelected = isSelected
        self.indent = indent
        self.useListStyling = useListStyling
        self.primaryAction = primaryAction
        self.onRename = onRename
        self.onDelete = onDelete
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
        let row = SelectableRow(
            isSelected: isSelected,
            insets: rowInsets,
            useListStyling: useListStyling,
            primaryAction: rowPrimaryAction
        ) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(isSelected ? selectedTextColor : secondaryTextColor)
                Text(title)
                    .appFont(SidebarTypography.primary)
                    .foregroundStyle(isSelected ? selectedTextColor : primaryTextColor)
                    .lineLimit(1)
                Spacer()
                if let count {
                    if count == 0 {
                        Image(appIcon: AppIcon.State.success)
                            .appFont(SidebarTypography.secondary)
                            .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                            .accessibilityLabel("No tasks")
                    } else {
                        Text("\(count)")
                            .appFont(SidebarTypography.secondary)
                            .foregroundStyle(isSelected ? selectedSecondaryText : secondaryTextColor)
                    }
                }
            }
        }
        .sidebarListSwipeActions(
            leadingTitle: onRename == nil ? nil : "Rename",
            onLeading: onRename,
            onDelete: onDelete
        )
        if contextMenuItems.isEmpty {
            row
        } else {
            row
                .platformContextMenu(items: contextMenuItems)
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

    private var contextMenuItems: [SidebarMenuItem] {
        var items: [SidebarMenuItem] = []
        if let onRename {
            items.append(.rename(handler: onRename))
        }
        if let onDelete {
            items.append(.delete(handler: onDelete))
        }
        return items
    }

    private var rowPrimaryAction: (() -> Void)? {
        primaryAction
    }
}
