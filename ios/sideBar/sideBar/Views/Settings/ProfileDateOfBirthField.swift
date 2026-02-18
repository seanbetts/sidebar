import SwiftUI

struct ProfileDateOfBirthField: View {
    @Binding var dateOfBirthEnabled: Bool
    @Binding var dateOfBirth: Date

    var body: some View {
        LabeledContent("Date of Birth") {
            if dateOfBirthEnabled {
                HStack(spacing: 8) {
                    DatePicker(
                        "Date of Birth",
                        selection: $dateOfBirth,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    #if os(iOS)
                    .datePickerStyle(.compact)
                    #endif

                    Button("Clear") {
                        dateOfBirthEnabled = false
                    }
                    .font(.caption)
                }
            } else {
                Button("Set") {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                }
                .font(.subheadline)
            }
        }
    }
}
