#if os(iOS)
import UIKit

@available(iOS 26.0, *)
final class EditorTextView: UITextView {
    override var inputAssistantItem: UITextInputAssistantItem {
        let item = super.inputAssistantItem
        item.leadingBarButtonGroups = []
        item.trailingBarButtonGroups = []
        return item
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        builder.remove(menu: .textStyle)
        builder.remove(menu: .format)
    }
}
#endif
