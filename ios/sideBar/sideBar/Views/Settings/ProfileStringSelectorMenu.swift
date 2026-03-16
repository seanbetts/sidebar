import SwiftUI

struct ProfileStringSelectorMenu: View {
    @Binding var selection: String
    let options: [String]
    let selectionLabel: String

    var body: some View {
        Picker(selectionLabel, selection: $selection) {
            Text("Not set").tag("")
            ForEach(options, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .appFont(.body)
    }
}
