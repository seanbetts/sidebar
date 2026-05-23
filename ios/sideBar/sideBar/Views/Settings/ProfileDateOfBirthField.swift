import SwiftUI
import sideBarShared

struct ProfileDateOfBirthField: View {
    @Binding var dateOfBirthEnabled: Bool
    @Binding var dateOfBirth: Date
    @State private var isDatePickerPresented = false

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
                Button {
                    isDatePickerPresented = true
                } label: {
                    SidebarSelectionTriggerLabel(
                        title: dateOfBirth.formatted(date: .abbreviated, time: .omitted)
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                    VStack(alignment: .trailing, spacing: DesignTokens.Spacing.sm) {
                        DatePicker(
                            "Date of Birth",
                            selection: $dateOfBirth,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.graphical)

                        Button("Done") {
                            isDatePickerPresented = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(DesignTokens.Spacing.md)
                    .frame(minWidth: 280)
                }

                Button {
                    dateOfBirthEnabled = false
                } label: {
                    Image(appIcon: AppIcon.Action.clearFilled)
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
            datePickerSheet
        }
    }

    private var iosContent: some View {
        HStack(spacing: 8) {
            if dateOfBirthEnabled {
                Button {
                    isDatePickerPresented = true
                } label: {
                    SidebarSelectionTriggerLabel(
                        title: dateOfBirth.formatted(date: .abbreviated, time: .omitted)
                    )
                    .profileIOSControlFrame()
                }
                .buttonStyle(.plain)

                Button {
                    dateOfBirthEnabled = false
                    isDatePickerPresented = false
                } label: {
                    Image(appIcon: AppIcon.Action.clearFilled)
                        .appFont(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear date of birth")
            } else {
                Button {
                    dateOfBirth = Date()
                    dateOfBirthEnabled = true
                    isDatePickerPresented = true
                } label: {
                    SidebarSelectionTriggerLabel(
                        title: "Not set",
                        isPlaceholder: true
                    )
                    .profileIOSControlFrame()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var datePickerSheet: some View {
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.md) {
            DatePicker(
                "Date of Birth",
                selection: $dateOfBirth,
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Button("Done") {
                isDatePickerPresented = false
            }
            .appFont(.body)
        }
        .padding(DesignTokens.Spacing.lg)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
    #endif
}
