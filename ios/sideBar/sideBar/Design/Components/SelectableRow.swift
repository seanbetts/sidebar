import SwiftUI

struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let content: Content
    private let primaryAction: (() -> Void)?
    private let rowInsets: EdgeInsets
    private let useListStyling: Bool
    private let verticalPadding: CGFloat
    private let customRowBackground: Color?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var usesButtonBackedPrimaryAction: Bool {
        primaryAction != nil
    }

    init(
        isSelected: Bool,
        insets: EdgeInsets = EdgeInsets(
            top: 0,
            leading: DesignTokens.Spacing.sm,
            bottom: 0,
            trailing: DesignTokens.Spacing.sm
        ),
        verticalPadding: CGFloat = DesignTokens.Spacing.xs,
        useListStyling: Bool = true,
        rowBackground: Color? = nil,
        primaryAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.rowInsets = insets
        self.useListStyling = useListStyling
        self.verticalPadding = verticalPadding
        self.customRowBackground = rowBackground
        self.primaryAction = primaryAction
        self.content = content()
    }

    var body: some View {
        let rowContent = content
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .animation(Motion.quick(reduceMotion: reduceMotion), value: isSelected)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityAddTraits(usesButtonBackedPrimaryAction ? .isButton : [])
            .onTapGesture {
                primaryAction?()
            }

        if useListStyling {
            rowContent
                .listRowInsets(rowInsets)
                .listRowBackground(selectedRowBackground)
                .sidebarHover($isHovered)
        } else {
            rowContent
                .padding(.leading, rowInsets.leading)
                .padding(.trailing, rowInsets.trailing)
                .background(selectedRowBackground)
                .sidebarHover($isHovered)
        }
    }

    private var selectedRowBackground: Color {
        if isSelected {
            return DesignTokens.Colors.selection
        }
        if isHovered && !isSelected {
            return DesignTokens.Colors.sidebarHoverBackground
        }
        return rowBackground
    }

    private var rowBackground: Color {
        if let customRowBackground {
            return customRowBackground
        }
        return DesignTokens.Colors.sidebarRowBackground
    }
}
