import SwiftUI
import sideBarShared

struct ProfileTextField: View {
    let label: String
    @Binding var text: String
    var autocapitalizesWords = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            field
            if !text.isEmpty {
                ProfileClearValueButton(accessibilityLabel: "Clear \(label.lowercased())") {
                    text = ""
                }
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        #if os(macOS)
        TextField(text: $text, prompt: Text("Not set")) {
        }
        .sidebarTextEntryField()
        .frame(maxWidth: 320)
        #else
        if autocapitalizesWords {
            iosField
                .textInputAutocapitalization(.words)
        } else {
            iosField
        }
        #endif
    }

    #if os(iOS)
    private var iosField: some View {
        TextField("Not set", text: $text)
            .multilineTextAlignment(.trailing)
            .sidebarTextEntryField()
            .profileIOSControlFrame()
    }
    #endif
}

struct ProfileClearValueButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(appIcon: AppIcon.Action.clearFilled)
                .appFont(.body)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(accessibilityLabel)
    }
}
