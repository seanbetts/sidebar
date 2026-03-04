#if os(iOS)
import UIKit

@available(iOS 26.0, *)
extension AttributedNoteTextSurface.Coordinator {
    func configureAccessoryToolbar(for textView: UITextView) {
        let capabilities = parent.enabledFormattingCapabilities
        guard !capabilities.isEmpty, parent.isEditable else {
            if textView.inputAccessoryView != nil {
                textView.inputAccessoryView = nil
                if textView.isFirstResponder {
                    textView.reloadInputViews()
                }
            }
            return
        }

        accessoryToolbarController.setEnabledCapabilities(capabilities)
        accessoryToolbarController.onAction = { [weak self, weak textView] action in
            guard let self, let textView else { return }
            self.handleAccessoryAction(action, in: textView)
        }

        let toolbarView = accessoryToolbarController.view
        if textView.inputAccessoryView !== toolbarView {
            textView.inputAccessoryView = toolbarView
            if textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }
    }

    func refreshToolbarState(in textView: UITextView) {
        accessoryToolbarController.setState(toolbarState(in: textView))
    }

    private func handleAccessoryAction(
        _ action: NoteInputAccessoryToolbarController.Action,
        in textView: UITextView
    ) {
        switch action {
        case .bold:
            toggleFontTrait(.traitBold, in: textView)
            refreshToolbarState(in: textView)
            textViewDidChange(textView)
        case .italic:
            toggleFontTrait(.traitItalic, in: textView)
            refreshToolbarState(in: textView)
            textViewDidChange(textView)
        case .underline:
            toggleAttribute(
                .underlineStyle,
                onValue: NSUnderlineStyle.single.rawValue,
                offValue: 0,
                in: textView
            )
            refreshToolbarState(in: textView)
            textViewDidChange(textView)
        case .bulletList:
            parent.onFormattingAction?(.bulletList)
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.refreshToolbarState(in: textView)
            }
        }
    }

    private func toggleFontTrait(
        _ trait: UIFontDescriptor.SymbolicTraits,
        in textView: UITextView
    ) {
        let range = clampedRange(textView.selectedRange, maxLength: textView.textStorage.length)
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let baseFont = (attrs[.font] as? UIFont)
                ?? textView.font
                ?? UIFont.preferredFont(forTextStyle: .body)
            attrs[.font] = toggledFont(baseFont, trait: trait)
            textView.typingAttributes = attrs
            return
        }

        textView.textStorage.beginEditing()
        textView.textStorage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let baseFont = (value as? UIFont)
                ?? (textView.typingAttributes[.font] as? UIFont)
                ?? textView.font
                ?? UIFont.preferredFont(forTextStyle: .body)
            textView.textStorage.addAttribute(
                .font,
                value: self.toggledFont(baseFont, trait: trait),
                range: subrange
            )
        }
        textView.textStorage.endEditing()
    }

    private func toggledFont(
        _ font: UIFont,
        trait: UIFontDescriptor.SymbolicTraits
    ) -> UIFont {
        var traits = font.fontDescriptor.symbolicTraits
        if traits.contains(trait) {
            traits.remove(trait)
        } else {
            traits.insert(trait)
        }
        guard let descriptor = font.fontDescriptor.withSymbolicTraits(traits) else {
            return font
        }
        return UIFont(descriptor: descriptor, size: font.pointSize)
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        onValue: Any,
        offValue: Any,
        in textView: UITextView
    ) {
        let range = clampedRange(textView.selectedRange, maxLength: textView.textStorage.length)
        if range.length == 0 {
            var attrs = textView.typingAttributes
            let current = (attrs[key] as? NSNumber)?.intValue ?? (attrs[key] as? Int ?? 0)
            attrs[key] = (current == 0) ? onValue : offValue
            textView.typingAttributes = attrs
            return
        }

        let current = (textView.textStorage.attribute(key, at: range.location, effectiveRange: nil) as? NSNumber)?
            .intValue
            ?? (textView.textStorage.attribute(key, at: range.location, effectiveRange: nil) as? Int ?? 0)
        let value: Any = current == 0 ? onValue : offValue
        textView.textStorage.addAttribute(key, value: value, range: range)
    }

    private func toolbarState(in textView: UITextView) -> NoteInputAccessoryToolbarState {
        var state = NoteInputAccessoryToolbarState()
        let textStorage = textView.textStorage
        guard textStorage.length > 0 else {
            return stateForTypingAttributes(textView.typingAttributes)
        }

        let selectedRange = clampedRange(textView.selectedRange, maxLength: textStorage.length)
        if selectedRange.length == 0 {
            let typingState = stateForTypingAttributes(textView.typingAttributes)
            if typingState.isBold || typingState.isItalic || typingState.isUnderline {
                return typingState
            }
            let index = min(selectedRange.location, textStorage.length - 1)
            let attrs = textStorage.attributes(at: index, effectiveRange: nil)
            return stateForAttributes(attrs)
        }

        var hasRun = false
        var allBold = true
        var allItalic = true
        var allUnderline = true
        textStorage.enumerateAttributes(in: selectedRange, options: []) { attrs, _, _ in
            hasRun = true
            let runState = stateForAttributes(attrs)
            allBold = allBold && runState.isBold
            allItalic = allItalic && runState.isItalic
            allUnderline = allUnderline && runState.isUnderline
        }
        if !hasRun {
            return state
        }
        state.isBold = allBold
        state.isItalic = allItalic
        state.isUnderline = allUnderline
        return state
    }

    private func stateForTypingAttributes(
        _ attrs: [NSAttributedString.Key: Any]
    ) -> NoteInputAccessoryToolbarState {
        stateForAttributes(attrs)
    }

    private func stateForAttributes(
        _ attrs: [NSAttributedString.Key: Any]
    ) -> NoteInputAccessoryToolbarState {
        var state = NoteInputAccessoryToolbarState()
        let font = (attrs[.font] as? UIFont)
            ?? UIFont.preferredFont(forTextStyle: .body)
        let traits = font.fontDescriptor.symbolicTraits
        state.isBold = traits.contains(.traitBold)
        state.isItalic = traits.contains(.traitItalic)
        let underline = (attrs[.underlineStyle] as? NSNumber)?.intValue
            ?? (attrs[.underlineStyle] as? Int ?? 0)
        state.isUnderline = underline != 0
        return state
    }
}
#endif
