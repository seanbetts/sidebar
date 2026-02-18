import SwiftUI
import Combine
import sideBarShared
#if canImport(UIKit)
import UIKit
#endif

// MARK: - WebsitesView

public struct WebsitesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.scenePhase) private var scenePhase
    @State private var exportDocument: MarkdownFileDocument?
    @State private var exportFilename: String = "website.md"
    @State private var isExporting = false
    @State private var isRenameDialogPresented = false
    @State private var renameValue: String = ""
    @State private var isDeleteAlertPresented = false

    public init() {
    }

    public var body: some View {
        WebsitesDetailView(
            viewModel: environment.websitesViewModel,
            exportDocument: $exportDocument,
            exportFilename: $exportFilename,
            isExporting: $isExporting,
            isRenameDialogPresented: $isRenameDialogPresented,
            renameValue: $renameValue,
            isDeleteAlertPresented: $isDeleteAlertPresented
        )
            .task {
                await environment.websitesViewModel.load(force: true)
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await environment.consumeExtensionEvents()
                    await environment.websitesViewModel.load(force: true)
                }
            }
            #if !os(macOS)
            .navigationTitle(websiteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if environment.websitesViewModel.active != nil, !isPhone {
                            websiteToolbarMenu
                        }
                    }
                }
            }
            #endif
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .sideBarMarkdown,
                defaultFilename: exportFilename
            ) { _ in
                exportDocument = nil
            }
            .alert(renameDialogTitle, isPresented: $isRenameDialogPresented) {
                TextField(renameDialogPlaceholder, text: $renameValue)
                    .submitLabel(.done)
                    .onSubmit {
                        commitRename()
                    }
                Button("Rename") {
                    commitRename()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    renameValue = ""
                }
            }
            .deleteConfirmationAlert(
                title: deleteDialogTitle,
                isPresented: $isDeleteAlertPresented,
                message: "This will remove the website and cannot be undone.",
                confirmAsDefaultAction: true,
                onConfirm: {
                    guard let websiteId = environment.websitesViewModel.active?.id else { return }
                    Task {
                        await environment.websitesViewModel.deleteWebsite(id: websiteId)
                    }
                },
                onCancel: { }
            )
    }

    private var websiteTitle: String {
        #if os(macOS)
        return "Websites"
        #else
        guard horizontalSizeClass == .compact else {
            return "Websites"
        }
        guard let website = environment.websitesViewModel.active else {
            return "Websites"
        }
        return website.title.isEmpty ? website.url : website.title
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    #if os(iOS)
    private var websiteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: [
                .pin(isPinned: isPinned) {
                    guard let websiteId = environment.websitesViewModel.active?.id else { return }
                    Task {
                        await environment.websitesViewModel.setPinned(id: websiteId, pinned: !isPinned)
                    }
                },
                .rename {
                    renameValue = environment.websitesViewModel.active?.title ?? ""
                    isRenameDialogPresented = true
                },
                .copy {
                    copyWebsiteContent()
                },
                SidebarMenuItem(title: "Copy Title", systemImage: "textformat", role: nil) {
                    copyWebsiteTitle()
                },
                SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                    copyWebsiteURL()
                },
                .share {
                    shareWebsiteURL()
                },
                .shareText {
                    shareWebsiteText()
                },
                .download {
                    exportWebsite()
                },
                .archive(isArchived: isArchived) {
                    archiveActiveWebsite()
                },
                .delete {
                    isDeleteAlertPresented = true
                }
            ],
            isCompact: isCompact
        )
        .disabled(environment.websitesViewModel.active == nil)
    }
    #endif

    private var isPinned: Bool {
        environment.websitesViewModel.active?.pinned == true
    }

    private var isArchived: Bool {
        environment.websitesViewModel.active?.archived == true
    }

    private var renameDialogTitle: String {
        "Rename website"
    }

    private var renameDialogPlaceholder: String {
        "Website title"
    }

    private var deleteDialogTitle: String {
        "Delete website"
    }

    private func commitRename() {
        guard let websiteId = environment.websitesViewModel.active?.id else { return }
        let updatedName = renameValue
        isRenameDialogPresented = false
        renameValue = ""
        Task {
            await environment.websitesViewModel.renameWebsite(id: websiteId, title: updatedName)
        }
    }

    private func archiveActiveWebsite() {
        guard let websiteId = environment.websitesViewModel.active?.id else { return }
        Task {
            await environment.websitesViewModel.setArchived(id: websiteId, archived: !isArchived)
        }
    }

    private func copyWebsiteContent() {
        guard let content = environment.websitesViewModel.active?.content, !content.isEmpty else { return }
        let stripped = MarkdownRendering.stripFrontmatter(content)
        guard !stripped.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = stripped
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(stripped, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == stripped {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == stripped {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func copyWebsiteURL() {
        guard let urlString = websiteSourceURL?.absoluteString, !urlString.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = urlString
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == urlString {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == urlString {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func copyWebsiteTitle() {
        guard let website = environment.websitesViewModel.active else { return }
        let title = website.title.isEmpty ? website.url : website.title
        guard !title.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = title
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(title, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == title {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == title {
                pasteboard.string = ""
            }
            #endif
        }
    }

    private func shareWebsiteURL() {
        guard let url = websiteSourceURL else { return }
        SystemSharePresenter.share(url: url)
    }

    private func shareWebsiteText() {
        guard let content = environment.websitesViewModel.active?.content, !content.isEmpty else { return }
        let plainText = MarkdownRendering.plainTextForWebsiteShare(content)
        guard !plainText.isEmpty else { return }
        SystemSharePresenter.share(text: plainText)
    }

    private func exportWebsite() {
        guard let website = environment.websitesViewModel.active else { return }
        let fallbackName = website.title.isEmpty ? "website" : website.title
        let stripped = MarkdownRendering.stripFrontmatter(website.content)
        guard !stripped.isEmpty else { return }
        exportFilename = "\(fallbackName).md"
        exportDocument = MarkdownFileDocument(text: stripped)
        isExporting = true
    }

    private var websiteSourceURL: URL? {
        guard let website = environment.websitesViewModel.active else { return nil }
        let urlString = (website.urlFull?.isEmpty == false) ? website.urlFull : website.url
        guard let urlString else { return nil }
        return URL(string: urlString)
    }
}
