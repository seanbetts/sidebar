import SwiftUI

struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let content: Content
    private let rowInsets: EdgeInsets
    private let useListStyling: Bool
    private let verticalPadding: CGFloat

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
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.rowInsets = insets
        self.useListStyling = useListStyling
        self.verticalPadding = verticalPadding
        self.content = content()
    }

    var body: some View {
        let rowContent = content
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        if useListStyling {
            rowContent
                .listRowInsets(rowInsets)
                .listRowBackground(isSelected ? DesignTokens.Colors.selection : rowBackground)
        } else {
            rowContent
                .padding(.leading, rowInsets.leading)
                .padding(.trailing, rowInsets.trailing)
                .background(isSelected ? DesignTokens.Colors.selection : rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        }
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }
}
