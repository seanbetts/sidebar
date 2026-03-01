import SwiftUI

struct ProfileDateOfBirthField: View {
    @Binding var dateOfBirthEnabled: Bool
    @Binding var dateOfBirth: Date

    var body: some View {
        LabeledContent {
            if dateOfBirthEnabled {
                HStack(spacing: 8) {
                    DatePicker(
                        "Date of Birth",
                        selection: $dateOfBirth,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .appFont(.body)
                    #if os(iOS)
                    .datePickerStyle(.compact)
                    #endif

                    Button {
                        dateOfBirthEnabled = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .appFont(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear date of birth")
                }
            } else {
                Button("Set") {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                }
                .appFont(.body)
            }
        } label: {
            Text("Date of Birth")
                .appFont(.body)
        }
    }
}
