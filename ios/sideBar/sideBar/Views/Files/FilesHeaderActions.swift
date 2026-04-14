import SwiftUI
import sideBarShared
import UniformTypeIdentifiers

enum FileShareAction {
    static func makeTemporaryShareURL(
        data: Data,
        filename: String,
        temporaryStore: TemporaryFileStore = .shared
    ) throws -> URL {
        try temporaryStore.store(data: data, filename: filename)
    }
}

struct FilesHeaderActions: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: IngestionViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var isRenameSheetPresented = false
    @State private var renameValue: String = ""
    @State private var isDeleteAlertPresented = false
    @State private var exportDocument: BinaryFileDocument?
    @State private var isExporting = false
    @State private var exportFilename: String = "file"

    var body: some View {
        HeaderActionRow(spacing: DesignTokens.Spacing.xs) {
            if shouldShowExpandButton {
                expandButton
            }
            fileActionsMenu
            closeButton
        }
        .deleteConfirmationAlert(
            title: deleteDialogTitle,
            isPresented: $isDeleteAlertPresented,
            message: "This will remove the file and cannot be undone.",
            onConfirm: {
                Task { await deleteActiveFile() }
            },
            onCancel: { }
        )
        .sheet(isPresented: $isRenameSheetPresented) {
            RenameItemSheet(
                title: "Rename File",
                placeholder: "File name",
                text: $renameValue
            ) { newName in
                Task { await renameFile(to: newName) }
            }
            .phoneSheetGrabBarVisible()
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .data,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.matches(
                    section: .files,
                    workspacePane: workspaceColumn.workspacePane
                  ) else { return }
            switch event.action {
            case .renameItem:
                beginRename()
            case .deleteItem:
                isDeleteAlertPresented = true
            case .openInDefaultApp:
                Task { await downloadFile() }
            case .quickLook:
                environment.toastCenter.show(message: "Quick Look is not available yet")
            default:
                break
            }
        }
    }

    private var fileActionsMenu: some View {
        #if os(macOS)
        HeaderActionMenuControl(
            systemName: "ellipsis",
            accessibilityLabel: "File options",
            chromeStyle: Self.actionControlChromeStyle
        ) {
            sidebarMenuItemsView(fileHeaderMenuItems)
        }
        .disabled(viewModel.selectedFileId == nil)
        #else
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "File options",
            items: fileHeaderMenuItems,
            isCompact: isCompact,
            chromeStyle: compactPhoneToolbarChromeStyle
        )
        .disabled(viewModel.selectedFileId == nil)
        #endif
    }

    private var fileHeaderMenuItems: [SidebarMenuItem] {
        var items: [SidebarMenuItem] = [
            .pin(isPinned: isPinned) {
                Task { await togglePin() }
            },
            .rename {
                beginRename()
            },
            .download {
                Task { await downloadFile() }
            },
            SidebarMenuItem(title: "Share", systemImage: "square.and.arrow.up", role: nil) {
                Task { await shareFile() }
            },
            .delete {
                isDeleteAlertPresented = true
            }
        ]
        if viewModel.canCopyTextForSelectedFile {
            items.insert(
                .copyText {
                    Task { await copySelectedFileContent() }
                },
                at: 2
            )
        }
        return items
    }

    private var shouldShowExpandButton: Bool {
        WorkspaceBehaviorPolicy.shouldShowExpandButton(
            workspaceColumn: workspaceColumn,
            isPhoneIdiom: {
                #if os(iOS)
                isPhone
                #else
                false
                #endif
            }()
        )
    }

    private var expandButton: some View {
        HeaderActionButton(
            systemName: expandButtonIconName,
            accessibilityLabel: expandButtonLabel,
            action: expandFilesView,
            chromeStyle: compactPhoneToolbarChromeStyle
        )
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand files"
    }

    private func expandFilesView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var compactPhoneToolbarChromeStyle: HeaderActionControlChromeStyle {
        #if os(iOS)
        return isCompact && isPhone ? .plain : Self.actionControlChromeStyle
        #else
        return Self.actionControlChromeStyle
        #endif
    }

    @ViewBuilder
    private var closeButton: some View {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            EmptyView()
        } else {
            HeaderActionButton(
                systemName: "xmark",
                accessibilityLabel: "Close file",
                action: {
                    viewModel.clearSelection()
                },
                isDisabled: viewModel.selectedFileId == nil,
                chromeStyle: Self.actionControlChromeStyle
            )
        }
        #else
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close file",
            action: {
                viewModel.clearSelection()
            },
            isDisabled: viewModel.selectedFileId == nil,
            chromeStyle: Self.actionControlChromeStyle
        )
        #endif
    }

    private var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    private var isPinned: Bool {
        if let meta = viewModel.activeMeta {
            return meta.file.pinned ?? false
        }
        guard let selectedId = viewModel.selectedFileId else { return false }
        return viewModel.items.first { $0.file.id == selectedId }?.file.pinned ?? false
    }

    private var selectedFilenameOriginal: String? {
        if let name = viewModel.activeMeta?.file.filenameOriginal {
            return name
        }
        guard let selectedId = viewModel.selectedFileId else {
            return nil
        }
        return viewModel.items.first { $0.file.id == selectedId }?.file.filenameOriginal
    }

    private var deleteDialogTitle: String {
        guard let name = selectedFilenameOriginal else {
            return "Delete file"
        }
        return "Delete \"\(stripFileExtension(name))\"?"
    }

    private func togglePin() async {
        guard let selectedId = viewModel.selectedFileId else { return }
        await viewModel.togglePinned(fileId: selectedId, pinned: !isPinned)
    }

    private func beginRename() {
        guard let name = selectedFilenameOriginal else { return }
        renameValue = stripFileExtension(name)
        isRenameSheetPresented = true
    }

    private func renameFile(to newName: String) async {
        guard let selectedId = viewModel.selectedFileId else { return }
        let originalName = selectedFilenameOriginal ?? newName
        let updatedName = applyFileExtension(originalName: originalName, newName: newName)
        let success = await viewModel.renameFile(fileId: selectedId, filename: updatedName)
        if !success {
            environment.toastCenter.show(message: "Failed to rename file")
        }
    }

    private func copySelectedFileContent() async {
        guard let fileId = viewModel.selectedFileId,
              let text = await viewModel.loadCopyTextContent(fileId: fileId) else {
            environment.toastCenter.show(message: "Text unavailable for this file")
            return
        }
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = text
        #endif
        environment.toastCenter.show(message: "Text copied", style: .success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == text {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == text {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func downloadFile() async {
        do {
            let payload = try await fileTransferPayload()
            exportDocument = BinaryFileDocument(data: payload.data)
            exportFilename = payload.filename
            isExporting = true
        } catch {
            environment.toastCenter.show(message: "Failed to download file")
        }
    }

    private func shareFile() async {
        do {
            let payload = try await fileTransferPayload()
            let url = try FileShareAction.makeTemporaryShareURL(
                data: payload.data,
                filename: payload.filename
            )
            await MainActor.run {
                SystemSharePresenter.share(url: url)
            }
        } catch {
            environment.toastCenter.show(message: "Failed to share file")
        }
    }

    private func fileTransferPayload() async throws -> (data: Data, filename: String) {
        guard let meta = viewModel.activeMeta else {
            throw FileTransferError.unavailable
        }
        guard let derivative = viewModel.preferredDownloadDerivative(for: meta) else {
            throw FileTransferError.unavailable
        }
        let data = try await environment.container.ingestionAPI.getContent(
            fileId: meta.file.id,
            kind: derivative.kind,
            range: nil
        )
        let filename = viewModel.makeFilename(
            base: meta.file.filenameOriginal,
            mimeType: derivative.mime,
            fallback: derivative.kind
        )
        return (data, filename)
    }

    private func deleteActiveFile() async {
        guard let selectedId = viewModel.selectedFileId else { return }
        let success = await viewModel.deleteFile(fileId: selectedId)
        if !success {
            environment.toastCenter.show(message: "Failed to delete file")
        }
    }

    private func applyFileExtension(originalName: String, newName: String) -> String {
        guard let extensionMatch = originalName.range(of: "\\.[^./]+$", options: .regularExpression) else {
            return newName
        }
        let ext = String(originalName[extensionMatch])
        if newName.hasSuffix(ext) {
            return newName
        }
        return newName + ext
    }

}

private enum FileTransferError: Error {
    case unavailable
}
