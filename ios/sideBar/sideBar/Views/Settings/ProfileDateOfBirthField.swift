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

                    Button {
                        dateOfBirthEnabled = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
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
                .font(.subheadline)
            }
        }
    }
}
