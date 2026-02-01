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
    @State private var isArchiveAlertPresented = false

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
            isDeleteAlertPresented: $isDeleteAlertPresented,
            isArchiveAlertPresented: $isArchiveAlertPresented
        )
            .task {
                await environment.websitesViewModel.load(force: true)
            }
            #if os(iOS)
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await environment.consumeExtensionEvents()
                    await environment.websitesViewModel.load(force: true)
                }
            }
            #endif
            #if !os(macOS)
            .navigationTitle(websiteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact, environment.websitesViewModel.active != nil, !isPhone {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        websiteToolbarMenu
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
            .alert(deleteDialogTitle, isPresented: $isDeleteAlertPresented) {
                Button("Delete", role: .destructive) {
                    guard let websiteId = environment.websitesViewModel.active?.id else { return }
                    Task {
                        await environment.websitesViewModel.deleteWebsite(id: websiteId)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will remove the website and cannot be undone.")
            }
            .alert(archiveAlertTitle, isPresented: $isArchiveAlertPresented) {
                Button(archiveActionTitle, role: .destructive) {
                    guard let websiteId = environment.websitesViewModel.active?.id else { return }
                    Task {
                        await environment.websitesViewModel.setArchived(id: websiteId, archived: !isArchived)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(archiveAlertMessage)
            }
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
                SidebarMenuItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                    guard let websiteId = environment.websitesViewModel.active?.id else { return }
                    Task {
                        await environment.websitesViewModel.setPinned(id: websiteId, pinned: !isPinned)
                    }
                },
                SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                    renameValue = environment.websitesViewModel.active?.title ?? ""
                    isRenameDialogPresented = true
                },
                SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                    copyWebsiteContent()
                },
                SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                    copyWebsiteURL()
                },
                SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                    exportWebsite()
                },
                SidebarMenuItem(title: archiveMenuTitle, systemImage: archiveIconName, role: nil) {
                    isArchiveAlertPresented = true
                },
                SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
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

    private var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    private var archiveMenuTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var archiveIconName: String {
        isArchived ? "archivebox.fill" : "archivebox"
    }

    private var archiveActionTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var archiveAlertTitle: String {
        isArchived ? "Unarchive website" : "Archive website"
    }

    private var archiveAlertMessage: String {
        isArchived
            ? "This will move the website back to your main list."
            : "This will move the website into your archive."
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

private struct WebsitesDetailView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @Environment(\.openURL) private var openURL
    @State private var safariURL: URL?
    @Binding var exportDocument: MarkdownFileDocument?
    @Binding var exportFilename: String
    @Binding var isExporting: Bool
    @Binding var isRenameDialogPresented: Bool
    @Binding var renameValue: String
    @Binding var isDeleteAlertPresented: Bool
    @Binding var isArchiveAlertPresented: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                header
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(environment.$shortcutActionEvent) { event in
            guard let event, event.section == .websites else { return }
            switch event.action {
            case .renameItem:
                guard viewModel.active != nil else { return }
                renameValue = displayTitle
                isRenameDialogPresented = true
            case .deleteItem:
                guard viewModel.active != nil else { return }
                isDeleteAlertPresented = true
            case .archiveItem:
                guard viewModel.active != nil else { return }
                isArchiveAlertPresented = true
            case .openInBrowser:
                openSource()
            default:
                break
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isCompact, sourceURL != nil {
                    Button(action: openInDefaultBrowser) {
                        Text(displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isCompact, viewModel.active != nil, isPhone {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if shouldShowExpandButton {
                        expandButton
                    }
                    websiteToolbarMenu
                }
            }
        }
        #endif
        #if os(iOS) && canImport(SafariServices)
        .sheet(isPresented: safariBinding) {
            if let safariURL {
                SafariView(url: safariURL)
            }
        }
        #endif
    }
}

extension WebsitesDetailView {
    private var header: some View {
        ContentHeaderRow(
            iconView: headerIcon,
            title: displayTitle,
            subtitle: subtitleText,
            titleLineLimit: 1,
            subtitleLineLimit: 1,
            titleLayoutPriority: 0,
            subtitleLayoutPriority: 1,
            onTitleTap: titleTapAction
        ) {
            if viewModel.active != nil {
                HeaderActionRow {
                    if shouldShowExpandButton {
                        expandButton
                    }
                    websiteActionsMenu
                    closeButton
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private var content: some View {
        if let website = viewModel.active {
            ScrollView {
                SideBarMarkdownContainer(text: website.content)
            }
        } else if viewModel.isLoadingDetail || viewModel.pendingWebsite != nil {
            LoadingView(message: "Reading...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.selectedWebsiteId != nil {
            PlaceholderView(
                title: "Unable to load website",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                guard let selectedId = viewModel.selectedWebsiteId else { return }
                Task { await viewModel.loadById(id: selectedId) }
            }
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingView(message: "Loading websites…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(
                title: "Select a website",
                subtitle: "Choose a website from the sidebar to read it.",
                iconName: "globe"
            )
        }
    }

    private var displayTitle: String {
        guard let website = viewModel.active else {
            return "Websites"
        }
        if !website.title.isEmpty {
            return website.title
        }
        return website.url
    }

    private var subtitleText: String? {
        guard let website = viewModel.active else {
            return nil
        }
        var parts: [String] = []
        let domain = website.domain.isEmpty ? website.url : website.domain
        parts.append(formatDomain(domain))
        if let publishedAt = website.publishedAt,
           let date = DateParsing.parseISO8601(publishedAt) {
            parts.append(Self.publishedDateFormatter.string(from: date))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private var headerIcon: AnyView {
        guard let website = viewModel.active else {
            return AnyView(
                Image(systemName: "globe")
                    .font(DesignTokens.Typography.titleLg)
                    .foregroundStyle(.primary)
            )
        }

        let hasFavicon = (website.faviconR2Key?.isEmpty == false)
            || (website.faviconUrl?.isEmpty == false)
        if hasFavicon {
            let faviconView = FaviconImageView(
                faviconUrl: website.faviconUrl,
                faviconR2Key: website.faviconR2Key,
                r2Endpoint: environment.container.config.r2Endpoint,
                r2FaviconBucket: environment.container.config.r2FaviconBucket,
                r2FaviconPublicBaseUrl: environment.container.config.r2FaviconPublicBaseUrl,
                size: 24,
                placeholderTint: DesignTokens.Colors.textPrimary
            )
            return AnyView(faviconView)
        }
        return AnyView(
            Image(systemName: "globe")
                .font(DesignTokens.Typography.titleLg)
                .foregroundStyle(.primary)
        )
    }

    private var websiteActionsMenu: some View {
        #if os(macOS)
        Menu {
            Button {
                guard let websiteId = viewModel.active?.id else { return }
                Task {
                    await viewModel.setPinned(id: websiteId, pinned: !isPinned)
                }
            } label: {
                Label(pinActionTitle, systemImage: pinIconName)
            }
            Button {
                renameValue = viewModel.active?.title ?? ""
                isRenameDialogPresented = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                copyWebsiteContent()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                copyWebsiteURL()
            } label: {
                Label("Copy URL", systemImage: "link")
            }
            Button {
                exportWebsite()
            } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
            Button {
                isArchiveAlertPresented = true
            } label: {
                Label(archiveMenuTitle, systemImage: archiveIconName)
            }
            Button(role: .destructive) {
                isDeleteAlertPresented = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            HeaderActionIcon(systemName: "ellipsis")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Website options")
        .disabled(viewModel.active == nil)
        #else
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: [
                SidebarMenuItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                    guard let websiteId = viewModel.active?.id else { return }
                    Task {
                        await viewModel.setPinned(id: websiteId, pinned: !isPinned)
                    }
                },
                SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                    renameValue = viewModel.active?.title ?? ""
                    isRenameDialogPresented = true
                },
                SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                    copyWebsiteContent()
                },
                SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                    copyWebsiteURL()
                },
                SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                    exportWebsite()
                },
                SidebarMenuItem(title: archiveMenuTitle, systemImage: archiveIconName, role: nil) {
                    isArchiveAlertPresented = true
                },
                SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
                    isDeleteAlertPresented = true
                }
            ],
            isCompact: isCompact
        )
        .disabled(viewModel.active == nil)
        #endif
    }

    #if os(iOS)
    private var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private var websiteToolbarMenu: some View {
        HeaderActionMenuButton(
            systemImage: "ellipsis",
            accessibilityLabel: "Website options",
            items: [
                SidebarMenuItem(title: pinActionTitle, systemImage: pinIconName, role: nil) {
                    guard let websiteId = viewModel.active?.id else { return }
                    Task {
                        await viewModel.setPinned(id: websiteId, pinned: !isPinned)
                    }
                },
                SidebarMenuItem(title: "Rename", systemImage: "pencil", role: nil) {
                    renameValue = viewModel.active?.title ?? ""
                    isRenameDialogPresented = true
                },
                SidebarMenuItem(title: "Copy", systemImage: "doc.on.doc", role: nil) {
                    copyWebsiteContent()
                },
                SidebarMenuItem(title: "Copy URL", systemImage: "link", role: nil) {
                    copyWebsiteURL()
                },
                SidebarMenuItem(title: "Download", systemImage: "square.and.arrow.down", role: nil) {
                    exportWebsite()
                },
                SidebarMenuItem(title: archiveMenuTitle, systemImage: archiveIconName, role: nil) {
                    isArchiveAlertPresented = true
                },
                SidebarMenuItem(title: "Delete", systemImage: "trash", role: .destructive) {
                    isDeleteAlertPresented = true
                }
            ],
            isCompact: isCompact
        )
        .disabled(viewModel.active == nil)
    }
    #endif

    private var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close website",
            action: { viewModel.clearSelection() },
            isDisabled: viewModel.active == nil
        )
    }

    private var expandButton: some View {
        Button(action: expandWebsiteView) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(DesignTokens.Typography.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
                .rotationEffect(.degrees(90))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Expand website")
        .disabled(viewModel.active == nil)
    }

    private var shouldShowExpandButton: Bool {
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    private var isPinned: Bool {
        viewModel.active?.pinned == true
    }

    private var isArchived: Bool {
        viewModel.active?.archived == true
    }

    private var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    private var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    private var archiveMenuTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var archiveIconName: String {
        isArchived ? "archivebox.fill" : "archivebox"
    }

    private var archiveActionTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private func openSource() {
        guard let url = sourceURL else { return }
        #if os(iOS) && canImport(SafariServices)
        safariURL = url
        #else
        openURL(url)
        #endif
    }

    private func openInDefaultBrowser() {
        guard let url = sourceURL else { return }
        openURL(url)
    }

    private func expandWebsiteView() {
        isWorkspaceExpanded.toggle()
    }

    private var titleTapAction: (() -> Void)? {
        guard sourceURL != nil else { return nil }
        return { openInDefaultBrowser() }
    }

    private func copyWebsiteContent() {
        guard let content = viewModel.active?.content, !content.isEmpty else { return }
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
        guard let urlString = sourceURL?.absoluteString, !urlString.isEmpty else { return }
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

    private func exportWebsite() {
        guard let website = viewModel.active else { return }
        let fallbackName = website.title.isEmpty ? "website" : website.title
        let stripped = MarkdownRendering.stripFrontmatter(website.content)
        guard !stripped.isEmpty else { return }
        exportFilename = "\(fallbackName).md"
        exportDocument = MarkdownFileDocument(text: stripped)
        isExporting = true
    }

    private var sourceURL: URL? {
        guard let website = viewModel.active else { return nil }
        let urlString = (website.urlFull?.isEmpty == false) ? website.urlFull : website.url
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    private func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var safariBinding: Binding<Bool> {
        Binding(
            get: { safariURL != nil },
            set: { isPresented in
                if !isPresented {
                    safariURL = nil
                }
            }
        )
    }

    private static let publishedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}
