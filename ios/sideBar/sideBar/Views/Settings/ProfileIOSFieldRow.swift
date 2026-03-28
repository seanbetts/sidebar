import SwiftUI

func profileIOSRowMinHeight() -> CGFloat {
    28
}

struct ProfileIOSFieldRow<Content: View>: View {
    let label: String
    private let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        LabeledContent {
            content
                .frame(maxWidth: .infinity, minHeight: profileIOSRowMinHeight(), alignment: .trailing)
        } label: {
            Text(label)
                .appFont(.body)
        }
    }
}
