import Foundation

private let blankNoteTitleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HHmmss"
    return formatter
}()

@MainActor
extension NotesViewModel {
    public func createBlankNote() async -> NotePayload? {
        let suffix = blankNoteTitleFormatter.string(from: Date())
        return await createNote(title: "Untitled \(suffix)", folder: nil)
    }
}
