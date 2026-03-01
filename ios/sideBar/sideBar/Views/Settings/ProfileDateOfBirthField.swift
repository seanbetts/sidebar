import SwiftUI

struct ProfileDateOfBirthField: View {
    @Binding var dateOfBirthEnabled: Bool
    @Binding var dateOfBirth: Date
    #if os(iOS)
    @State private var isDatePickerPresented = false
    #endif

    var body: some View {
        LabeledContent {
            if dateOfBirthEnabled {
                #if os(iOS)
                HStack(spacing: 8) {
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
                }
                #else
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
                #endif
            } else {
                Button("Set") {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                    #if os(iOS)
                    isDatePickerPresented = true
                    #endif
                }
                .appFont(.body)
            }
        } label: {
            Text("Date of Birth")
                .appFont(.body)
        }
        #if os(iOS)
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
        #endif
    }
}
