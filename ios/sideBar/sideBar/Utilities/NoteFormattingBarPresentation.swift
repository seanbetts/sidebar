enum NoteFormattingBarPresentation: Equatable {
    case hidden
    case floatingTopTrailing
    case keyboardAccessory

    static func resolve(
        isEditing: Bool,
        isPhone: Bool,
        isSoftwareKeyboardVisible: Bool,
        isHardwareKeyboardInputExpected: Bool
    ) -> Self {
        guard isEditing else { return .hidden }
        guard isPhone else { return .floatingTopTrailing }
        if isSoftwareKeyboardVisible {
            return .keyboardAccessory
        }
        if isHardwareKeyboardInputExpected {
            return .floatingTopTrailing
        }
        return .hidden
    }
}
