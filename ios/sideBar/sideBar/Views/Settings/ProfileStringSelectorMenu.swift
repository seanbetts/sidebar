import SwiftUI

struct ProfileStringSelectorMenu: View {
    @Binding var selection: String
    let options: [String]
    let selectionLabel: String

    var body: some View {
        Menu {
            Button("Not set") {
                selection = ""
            }
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection = option
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.isEmpty ? "Not set" : selection)
                    .appFont(.body)
                    .foregroundStyle(
                        selection.isEmpty
                            ? DesignTokens.Colors.textSecondary
                            : DesignTokens.Colors.textPrimary
                    )
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectionLabel)
    }
}
