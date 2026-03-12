enum NoteFormattingBarPresentation: Equatable {
    case hidden
    case floatingTopTrailing
    case keyboardAccessory

    static func resolve(
        isEditing: Bool,
        isPhone: Bool,
        isSoftwareKeyboardVisible: Bool
    ) -> Self {
        guard isEditing else { return .hidden }
        guard isPhone else { return .floatingTopTrailing }
        if isSoftwareKeyboardVisible {
            return .keyboardAccessory
        }
        return .floatingTopTrailing
    }
}
