import SwiftUI
import sideBarShared

struct ProfileStringSelectorMenu: View {
    @Binding var selection: String
    let options: [String]
    let selectionLabel: String
    #if os(iOS)
    @State private var isPickerPresented = false
    #endif

    var body: some View {
        #if os(iOS)
        iosBody
        #else
        macBody
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                isPickerPresented = true
            } label: {
                SidebarSelectionTriggerLabel(
                    title: Self.displayTitle(for: selection),
                    isPlaceholder: selection.isEmpty
                )
                .profileIOSControlFrame()
            }
            .buttonStyle(.plain)

            if !selection.isEmpty {
                ProfileClearValueButton(
                    accessibilityLabel: "Clear \(selectionLabel.lowercased())"
                ) {
                    selection = ""
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            NavigationStack {
                List {
                    ForEach([""] + options, id: \.self) { option in
                        Button {
                            selection = option
                            isPickerPresented = false
                        } label: {
                            HStack {
                                Text(Self.displayTitle(for: option))
                                Spacer()
                                if option == selection {
                                    Image(appIcon: AppIcon.State.selectionCheck)
                                        .foregroundStyle(DesignTokens.Colors.actionPrimary)
                                }
                            }
                        }
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                }
                .navigationTitle(selectionLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPickerPresented = false
                        }
                    }
                }
            }
        }
    }
    #else
    private var macBody: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            SidebarSelectionMenu(
                selection: $selection,
                options: [""] + options,
                accessibilityLabel: selectionLabel,
                title: Self.displayTitle,
                isPlaceholder: { $0.isEmpty }
            )
            if !selection.isEmpty {
                ProfileClearValueButton(
                    accessibilityLabel: "Clear \(selectionLabel.lowercased())"
                ) {
                    selection = ""
                }
            }
        }
    }
    #endif

    static func displayTitle(for option: String) -> String {
        option.isEmpty ? "Not set" : tidiedDisplayTitle(for: option)
    }

    private static func tidiedDisplayTitle(for option: String) -> String {
        option
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { titleCasedPhrase(String($0)) }
            .joined(separator: "/")
    }

    private static func titleCasedPhrase(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return first.uppercased() + trimmed.dropFirst()
    }
}
