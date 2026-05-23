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
                    isPickerPresented = false
                }
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            selectorSheet
        }
    }

    private var selectorSheet: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(selectionLabel)
                .appFont(.subheading)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach([""] + options, id: \.self) { option in
                        Button {
                            selection = option
                            isPickerPresented = false
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.sm) {
                                Text(Self.displayTitle(for: option))
                                    .appFont(.body)
                                    .foregroundStyle(
                                        option.isEmpty
                                            ? DesignTokens.Colors.textSecondary
                                            : DesignTokens.Colors.textPrimary
                                    )
                                Spacer()
                                if option == selection {
                                    Image(appIcon: AppIcon.State.selectionCheck)
                                        .foregroundStyle(DesignTokens.Colors.actionPrimary)
                                }
                            }
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sidebarTextEntrySurface()
            }

            Button("Cancel") {
                isPickerPresented = false
            }
            .appFont(.body)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(DesignTokens.Spacing.lg)
        .presentationDetents([.height(selectorSheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var selectorSheetHeight: CGFloat {
        min(520, CGFloat(120 + (options.count + 1) * 48))
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
