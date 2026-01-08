import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var tree: FileTree? = nil
    @Published public private(set) var activeNote: NotePayload? = nil
    @Published public private(set) var errorMessage: String? = nil

    private let api: NotesAPI

    public init(api: NotesAPI) {
        self.api = api
    }

    public func loadTree() async {
        errorMessage = nil
        do {
            tree = try await api.listTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func loadNote(id: String) async {
        errorMessage = nil
        do {
            activeNote = try await api.getNote(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
