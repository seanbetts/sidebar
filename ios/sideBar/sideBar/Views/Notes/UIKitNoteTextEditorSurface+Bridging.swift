#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension UIKitNoteTextEditorSurface {
    func bridgedAttributedText(from text: AttributedString) -> NSAttributedString {
        SelectableNoteReadView.bridgedPlatformAttributedString(
            from: text,
            baseFontSize: viewModel.baseFontSize
        )
    }

    func bridgedTypingAttributes(from text: AttributedString) -> [NSAttributedString.Key: Any] {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(viewModel.typingAttributesForInsertion(in: text))
        let bridged = SelectableNoteReadView.bridgedPlatformAttributedString(
            from: sample,
            baseFontSize: viewModel.baseFontSize
        )
        return bridged.attributes(at: 0, effectiveRange: nil)
    }
}
#endif
