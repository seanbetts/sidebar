import SwiftUI

struct ProfileGenderSelectorMenu: View {
    @Binding var selection: String
    let options: [String]

    var body: some View {
        Menu {
            Button {
                selection = ""
            } label: {
                if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Not set", systemImage: "checkmark")
                } else {
                    Text("Not set")
                }
            }
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if ProfileSettingsView.pickerValuesEquivalent(option, selection) {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(displayValue)
                    .appFont(.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .appFont(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    private var displayValue: String {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not set" : selection
    }
}
