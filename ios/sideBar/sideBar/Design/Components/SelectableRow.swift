import SwiftUI

struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let content: Content
    private let rowInsets: EdgeInsets
    private let useListStyling: Bool

    init(
        isSelected: Bool,
        insets: EdgeInsets = EdgeInsets(
            top: 0,
            leading: DesignTokens.Spacing.sm,
            bottom: 0,
            trailing: DesignTokens.Spacing.sm
        ),
        useListStyling: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.rowInsets = insets
        self.useListStyling = useListStyling
        self.content = content()
    }

    var body: some View {
        let rowContent = content
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

        if useListStyling {
            rowContent
                .listRowInsets(rowInsets)
                .listRowBackground(isSelected ? DesignTokens.Colors.selection : DesignTokens.Colors.sidebar)
        } else {
            rowContent
                .padding(.leading, rowInsets.leading)
                .padding(.trailing, rowInsets.trailing)
                .background(isSelected ? DesignTokens.Colors.selection : DesignTokens.Colors.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm, style: .continuous))
        }
    }
}
