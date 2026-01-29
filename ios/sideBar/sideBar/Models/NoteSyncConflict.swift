import Foundation

struct NoteSyncConflict: Identifiable, Equatable {
    let id: UUID
    let noteId: String
    let noteName: String
    let notePath: String
    let localContent: String
    let serverContent: String
    let localDate: Date
    let serverDate: Date
}

func shouldPresentNoteConflict(
    localContent: String,
    localDate: Date,
    serverContent: String,
    serverDate: Date
) -> Bool {
    guard localContent != serverContent else { return false }
    return serverDate > localDate
}
