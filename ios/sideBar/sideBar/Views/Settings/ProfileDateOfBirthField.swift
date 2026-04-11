import SwiftUI

struct ProfileDateOfBirthField: View {
    @Binding var dateOfBirthEnabled: Bool
    @Binding var dateOfBirth: Date
    #if os(iOS)
    @State private var isDatePickerPresented = false
    #endif

    var body: some View {
        #if os(macOS)
        FormField("Date of Birth") {
            macContent
        }
        #else
        iosBody
        #endif
    }

    #if os(macOS)
    private var macContent: some View {
        HStack(spacing: 8) {
            if dateOfBirthEnabled {
                DatePicker(
                    "Date of Birth",
                    selection: $dateOfBirth,
                    displayedComponents: .date
                )
                .labelsHidden()
                .appFont(.body)

                Button {
                    dateOfBirthEnabled = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear date of birth")
            } else {
                Button("Set") {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                }
                .appFont(.body)
            }
        }
        .frame(maxWidth: 320, alignment: .trailing)
    }
    #endif

    #if os(iOS)
    private var iosBody: some View {
        FormField("Date of Birth") {
            iosContent
        }
        .sheet(isPresented: $isDatePickerPresented) {
            NavigationStack {
                Form {
                    DatePicker(
                        "Date of Birth",
                        selection: $dateOfBirth,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }
                .navigationTitle("Date of Birth")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            isDatePickerPresented = false
                        }
                    }
                }
            }
        }
    }

    private var iosContent: some View {
        HStack(spacing: 8) {
            if dateOfBirthEnabled {
                Button {
                    isDatePickerPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Text(dateOfBirth.formatted(date: .abbreviated, time: .omitted))
                            .appFont(.body)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .appFont(.caption2)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    dateOfBirthEnabled = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .appFont(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear date of birth")
            } else {
                Button("Set") {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                    isDatePickerPresented = true
                }
                .appFont(.body)
            }
        }
    }
    #endif
}
