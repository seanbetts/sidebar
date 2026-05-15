import SwiftUI

func profileIOSRowMinHeight() -> CGFloat {
    FormFieldLayoutMetrics.settingsIOSMinHeight
}

func profileIOSControlMaxWidth() -> CGFloat {
    320
}

extension View {
    func profileIOSControlFrame() -> some View {
        frame(maxWidth: profileIOSControlMaxWidth(), alignment: .trailing)
    }
}
