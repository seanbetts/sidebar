import Foundation
import Combine
import os

@MainActor
public final class NotesEditorViewModel: ObservableObject {
    @Published public private(set) var content: String = ""
    @Published public private(set) var attributedContent: NSAttributedString = NSAttributedString(string: "")
    @Published public private(set) var isDirty: Bool = false
    @Published public private(set) var isSaving: Bool = false
    @Published public private(set) var saveError: String? = nil
    @Published public private(set) var lastSaved: Date? = nil
    @Published public private(set) var currentNoteId: String? = nil
    @Published public private(set) var isReadOnly: Bool = false
    @Published public var selectedRange: NSRange = NSRange(location: 0, length: 0)
    @Published public private(set) var hasExternalUpdate: Bool = false

    private let api: any NotesProviding
    private let notesStore: NotesStore
    private let notesViewModel: NotesViewModel
    private let toastCenter: ToastCenter
    private let logger = Logger(subsystem: "sideBar", category: "NotesEditor")
    private var cancellables = Set<AnyCancellable>()
    private var saveTask: Task<Void, Never>?
    private var baselineContent: String = ""
    private var pendingExternalContent: String? = nil
    private var ignoreNextStoreUpdate = false
    private var isSaveInProgress = false
    private var pendingSaveRequested = false
    private let autosaveDelaySeconds: UInt64 = 1_500_000_000

    public init(
        api: any NotesProviding,
        notesStore: NotesStore,
        notesViewModel: NotesViewModel,
        toastCenter: ToastCenter
    ) {
        self.api = api
        self.notesStore = notesStore
        self.notesViewModel = notesViewModel
        self.toastCenter = toastCenter

        notesViewModel.$activeNote
            .sink { [weak self] note in
                self?.handleNoteUpdate(note)
            }
            .store(in: &cancellables)
    }

    public func updateSelection(_ range: NSRange) {
        selectedRange = range
    }

    public func handleUserEdit(_ updated: NSAttributedString) {
        attributedContent = updated
        content = MarkdownFormatting.serialize(attributedText: updated)
        isDirty = content != baselineContent
        saveError = nil
        scheduleAutosave()
    }

    public func applyBold() {
        applyInline(prefix: "**", suffix: "**", placeholder: "bold")
    }

    public func applyItalic() {
        applyInline(prefix: "*", suffix: "*", placeholder: "italic")
    }

    public func applyStrikethrough() {
        applyInline(prefix: "~~", suffix: "~~", placeholder: "strike")
    }

    public func applyInlineCode() {
        applyInline(prefix: "`", suffix: "`", placeholder: "code")
    }

    public func applyHeading(level: Int) {
        let prefix = String(repeating: "#", count: max(1, min(level, 3))) + " "
        applyLinePrefix(prefix: prefix)
    }

    public func applyBulletList() {
        applyLinePrefix(prefix: "- ")
    }

    public func applyOrderedList() {
        applyOrderedListPrefix()
    }

    public func applyTaskList() {
        applyTaskListPrefix()
    }

    public func applyBlockquote() {
        applyLinePrefix(prefix: "> ")
    }

    public func insertHorizontalRule() {
        insertBlock("\n---\n")
    }

    public func insertLink() {
        let result = MarkdownEditing.insertLink(text: content, range: selectedRange)
        applyEdit(result)
    }

    public func insertCodeBlock() {
        let result = MarkdownEditing.insertCodeBlock(text: content, range: selectedRange)
        applyEdit(result)
    }

    public func insertTable() {
        let result = MarkdownEditing.insertTable(text: content, range: selectedRange)
        applyEdit(result)
    }

    public func acceptExternalUpdate() {
        guard let pending = pendingExternalContent else { return }
        pendingExternalContent = nil
        hasExternalUpdate = false
        updateContentFromServer(pending)
    }

    public func dismissExternalUpdate() {
        pendingExternalContent = nil
        hasExternalUpdate = false
    }

    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        Task { [weak self] in
            await self?.saveIfNeeded()
        }
    }

    private func applyInline(prefix: String, suffix: String, placeholder: String) {
        let result = MarkdownEditing.applyInlineStyle(
            text: content,
            range: selectedRange,
            prefix: prefix,
            suffix: suffix,
            placeholder: placeholder
        )
        applyEdit(result)
    }

    private func applyLinePrefix(prefix: String) {
        let result = MarkdownEditing.toggleLinePrefix(
            text: content,
            range: selectedRange,
            prefix: prefix
        )
        applyEdit(result)
    }

    private func applyOrderedListPrefix() {
        let result = MarkdownEditing.toggleOrderedList(
            text: content,
            range: selectedRange
        )
        applyEdit(result)
    }

    private func applyTaskListPrefix() {
        let result = MarkdownEditing.toggleTaskList(
            text: content,
            range: selectedRange
        )
        applyEdit(result)
    }

    private func insertBlock(_ block: String) {
        let safeRange = selectedRange
        let updated = (content as NSString).replacingCharacters(in: safeRange, with: block)
        let selectionLocation = safeRange.location + block.utf16.count
        let result = MarkdownEditResult(
            text: updated,
            selectedRange: NSRange(location: selectionLocation, length: 0)
        )
        applyEdit(result)
    }

    private func applyEdit(_ result: MarkdownEditResult) {
        content = result.text
        attributedContent = MarkdownFormatting.render(markdown: result.text)
        selectedRange = result.selectedRange
        isDirty = content != baselineContent
        saveError = nil
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        guard isDirty, currentNoteId != nil, !isReadOnly else { return }
        if !isSaveInProgress {
            saveTask?.cancel()
            saveTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.autosaveDelaySeconds)
                self.saveTask = nil
                Task { [weak self] in
                    await self?.saveIfNeeded()
                }
            }
        } else {
            pendingSaveRequested = true
        }
    }

    private func saveIfNeeded() async {
        guard isDirty, let noteId = currentNoteId, !isReadOnly else { return }
        if isSaveInProgress {
            pendingSaveRequested = true
            return
        }
        isSaving = true
        isSaveInProgress = true
        saveError = nil
        do {
            let updated = try await api.updateNote(id: noteId, content: content)
            ignoreNextStoreUpdate = true
            notesStore.applyEditorUpdate(updated)
            baselineContent = updated.content
            isDirty = false
            lastSaved = Date()
        } catch {
            saveError = "Unable to save"
            if let apiError = error as? APIClientError {
                switch apiError {
                case .apiError(let message):
                    toastCenter.show(message: "Unable to save note: \(message)")
                    logger.error("Save failed: \(message, privacy: .public)")
                case .requestFailed(let statusCode):
                    toastCenter.show(message: "Unable to save note (HTTP \(statusCode))")
                    logger.error("Save failed: HTTP \(statusCode)")
                default:
                    toastCenter.show(message: "Unable to save note")
                    logger.error("Save failed: \(String(describing: apiError), privacy: .public)")
                }
            } else {
                toastCenter.show(message: "Unable to save note")
                logger.error("Save failed: \(String(describing: error), privacy: .public)")
            }
        }
        isSaving = false
        isSaveInProgress = false
        if pendingSaveRequested {
            pendingSaveRequested = false
            await saveIfNeeded()
        }
    }

    private func handleNoteUpdate(_ note: NotePayload?) {
        saveTask?.cancel()
        saveError = nil
        guard let note else {
            currentNoteId = nil
            content = ""
            attributedContent = NSAttributedString(string: "")
            baselineContent = ""
            isDirty = false
            lastSaved = nil
            hasExternalUpdate = false
            pendingExternalContent = nil
            return
        }

        if note.id == currentNoteId, note.content == content {
            if ignoreNextStoreUpdate {
                ignoreNextStoreUpdate = false
            }
            baselineContent = content
            if let modified = note.modified {
                lastSaved = Date(timeIntervalSince1970: modified)
            }
            isDirty = false
            return
        }

        currentNoteId = note.id
        let incoming = note.content
        if isDirty, incoming != content {
            pendingExternalContent = incoming
            hasExternalUpdate = true
            return
        }

        updateContentFromServer(incoming)
        if let modified = note.modified {
            lastSaved = Date(timeIntervalSince1970: modified)
        } else {
            lastSaved = nil
        }
    }

    private func updateContentFromServer(_ updated: String) {
        content = updated
        attributedContent = MarkdownFormatting.render(markdown: updated)
        baselineContent = updated
        isDirty = false
        hasExternalUpdate = false
        pendingExternalContent = nil
        selectedRange = NSRange(location: 0, length: 0)
    }
}
