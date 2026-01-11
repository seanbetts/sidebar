import SwiftUI

struct SelectableRow<Content: View>: View {
    let isSelected: Bool
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(isSelected: Bool, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, DesignTokens.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(
                top: 0,
                leading: DesignTokens.Spacing.sm,
                bottom: 0,
                trailing: DesignTokens.Spacing.sm
            ))
            .contentShape(Rectangle())
            .listRowBackground(isSelected ? selectionBackground : rowBackground)
    }

    private var selectionBackground: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    private var rowBackground: Color {
        colorScheme == .dark ? Color.black : Color.platformSystemBackground
    }
}
