import SwiftUI

func profileIOSRowMinHeight() -> CGFloat {
    FormFieldLayoutMetrics.settingsIOSMinHeight
}

func profileIOSControlMaxWidth() -> CGFloat {
    320
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

extension View {
    func profileIOSControlFrame() -> some View {
        frame(maxWidth: profileIOSControlMaxWidth(), alignment: .trailing)
    }
}
