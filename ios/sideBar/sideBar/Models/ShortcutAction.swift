import Foundation

public enum ShortcutListDirection: String, Hashable {
    case next
    case previous
}

public enum ShortcutAction: Hashable {
    case navigate(AppSection)
    case openSettings
    case newItem
    case closeItem
    case focusSearch
    case refreshSection
    case showShortcuts
    case openScratchpad
    case toggleSidebar
    case sendMessage
    case attachFile
    case renameItem
    case deleteItem
    case pinItem
    case archiveItem
    case openInBrowser
    case saveNote
    case toggleEditMode
    case formatBold
    case formatItalic
    case insertCodeBlock
    case createFolder
    case navigateList(ShortcutListDirection)
    case openInDefaultApp
    case quickLook
}
