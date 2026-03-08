import SwiftUI

struct CompactPhoneDockTapDismissModifier: ViewModifier {
    let isEnabled: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(
                TapGesture().onEnded {
                    onDismiss()
                }
            )
        } else {
            content
        }
    }
}
