import SwiftUI

func profileIOSRowMinHeight() -> CGFloat {
    FormFieldLayoutMetrics.settingsIOSMinHeight
}

struct ProfileIOSFieldRow<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        FormField(label) {
            content
        }
    }
}
