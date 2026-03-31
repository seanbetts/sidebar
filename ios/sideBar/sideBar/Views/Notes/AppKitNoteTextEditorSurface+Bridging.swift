#if os(macOS)
import AppKit
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
extension AppKitNoteTextEditorSurface {
    func bridgedAttributedText(from text: AttributedString) -> NSAttributedString {
        SelectableNoteReadView.bridgedPlatformEditorAttributedString(
            from: text,
            document: viewModel.currentPersistenceSnapshot().document,
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
