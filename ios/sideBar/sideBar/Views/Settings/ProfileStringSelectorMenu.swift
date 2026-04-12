import SwiftUI

struct ProfileStringSelectorMenu: View {
    @Binding var selection: String
    let options: [String]
    let selectionLabel: String

    var body: some View {
        SidebarSelectionMenu(
            selection: $selection,
            options: [""] + options,
            accessibilityLabel: selectionLabel,
            title: { option in
                option.isEmpty ? "Not set" : option
            },
            isPlaceholder: { $0.isEmpty }
        )
    }
}
