import Foundation
import sideBarShared
import SwiftUI

// MARK: - WebsitesPanel

public struct WebsitesPanel: View {
    @EnvironmentObject var appEnvironment: AppEnvironment

    public init() {
    }

    public var body: some View {
        WebsitesPanelView(viewModel: appEnvironment.websitesViewModel)
    }
}

struct WebsitesPanelView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @EnvironmentObject var appEnvironment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchQuery: String = ""
    @State private var hasLoaded = false
    @State private var isArchiveExpanded = false
    @State private var selection: String?
    @State private var listAppeared = false
    @State private var isNewWebsitePresented = false
    @State private var newWebsiteUrl: String = ""
    @State private var saveErrorMessage: String?
    @State var deleteTarget: WebsiteItem?
    @State var renameTarget: WebsiteItem?
    @State var renameValue: String = ""
    @State var isRenameDialogPresented = false
    @State var exportDocument: MarkdownFileDocument?
    @State var isExporting = false
    @State var exportFilename: String = "website"
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let base = VStack(spacing: 0) {
            header
            #if os(macOS)
            websitesPanelContentWithArchive
            #else
            content
            #endif
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task { await viewModel.load() }
            }
            if selection == nil {
                selection = viewModel.active?.id
            }
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.active?.id) { _, newValue in
            selection = newValue
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
        .onChange(of: isArchiveExpanded) { _, expanded in
            if expanded {
                Task { await viewModel.loadArchived() }
            }
        }
        return base
        .alert("Save a website", isPresented: $isNewWebsitePresented) {
            TextField("example.com", text: $newWebsiteUrl)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                #if os(iOS)
                .submitLabel(.done)
                #endif
                .onSubmit {
                    saveWebsite()
                }
            Button(viewModel.isSavingWebsite ? "Saving..." : "Save") {
                saveWebsite()
            }
            .disabled(viewModel.isSavingWebsite || !WebsiteURLValidator.isValid(newWebsiteUrl))
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                newWebsiteUrl = ""
            }
        }
        .alert("Unable to save website", isPresented: isSaveErrorPresented) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Failed to save website. Please try again.")
        }
        .alert("Delete website", isPresented: isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                guard let item = deleteTarget else { return }
                deleteTarget = nil
                Task { await viewModel.deleteWebsite(id: item.id) }
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("This will remove the website and cannot be undone.")
        }
        .alert("Rename website", isPresented: $isRenameDialogPresented) {
            TextField("Website name", text: $renameValue)
                .submitLabel(.done)
                .onSubmit {
                    commitRename()
                }
            Button("Rename") {
                commitRename()
            }
            .keyboardShortcut(.defaultAction)
            Button("Cancel", role: .cancel) {
                renameTarget = nil
                renameValue = ""
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .sideBarMarkdown,
            defaultFilename: exportFilename
        ) { _ in
            exportDocument = nil
        }
        .onReceive(appEnvironment.$shortcutActionEvent) { event in
            guard let event, event.section == .websites else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            case .newItem:
                newWebsiteUrl = ""
                isNewWebsitePresented = true
            case .navigateList(let direction):
                navigateWebsitesList(direction: direction)
            default:
                break
            }
        }
    }
}

extension WebsitesPanelView {
    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Websites") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Button {
                        newWebsiteUrl = ""
                        isNewWebsitePresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add website")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search websites", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load() }
            }
        } else if !searchQuery.trimmed.isEmpty {
            List {
                if let pending = viewModel.pendingWebsite {
                    Section("Adding") {
                        PendingWebsiteRow(pending: pending, useListStyling: true)
                    }
                }
                Section("Results") {
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        } else {
            List {
                if !pinnedItemsSorted.isEmpty || !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                    if !pinnedItemsSorted.isEmpty {
                        Section("Pinned") {
                            ForEach(Array(pinnedItemsSorted.enumerated()), id: \.element.id) { index, item in
                                websiteListRow(item: item, index: index)
                            }
                        }
                    }

                    if !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                        Section("Websites") {
                            if let pending = viewModel.pendingWebsite {
                                PendingWebsiteRow(pending: pending, useListStyling: true)
                            }
                            ForEach(Array(mainItems.enumerated()), id: \.element.id) { index, item in
                                websiteListRow(item: item, index: index)
                            }
                        }
                    }
                }
#if !os(macOS)
                Section {
                    DisclosureGroup(
                        isExpanded: $isArchiveExpanded,
                        content: {
                            if isArchiveLoading && archivedItems.isEmpty {
                                archiveLoadingRow(message: "Loading archived websites...")
                            }
                            if archivedItems.isEmpty {
                                Text(archivedEmptyStateText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                                    websiteListRow(item: item, index: index, allowArchive: false)
                                }
                            }
                        },
                        label: {
                            archiveLabel
                        }
                    )
                    .listRowBackground(rowBackground)
                }
#endif
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    @ViewBuilder
    private var websitesPanelContentWithArchive: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                Task { await viewModel.load() }
            }
        } else if !searchQuery.trimmed.isEmpty {
            List {
                if let pending = viewModel.pendingWebsite {
                    Section("Adding") {
                        PendingWebsiteRow(pending: pending, useListStyling: true)
                    }
                }
                Section("Results") {
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        } else {
            VStack(spacing: 0) {
                websitesListView
                websitesArchiveSection
            }
        }
    }

    private var websitesListView: some View {
        List {
            if !pinnedItemsSorted.isEmpty || !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                if !pinnedItemsSorted.isEmpty {
                    Section("Pinned") {
                        ForEach(Array(pinnedItemsSorted.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }

                if !mainItems.isEmpty || viewModel.pendingWebsite != nil {
                    Section("Websites") {
                        if let pending = viewModel.pendingWebsite {
                            PendingWebsiteRow(pending: pending, useListStyling: true)
                        }
                        ForEach(Array(mainItems.enumerated()), id: \.element.id) { index, item in
                            websiteListRow(item: item, index: index)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(panelBackground)
        .refreshable {
            await viewModel.load()
        }
    }
}

extension WebsitesPanelView {
    private func open(item: WebsiteItem) {
        selection = item.id
        Task { await viewModel.selectWebsite(id: item.id) }
    }

    private func navigateWebsitesList(direction: ShortcutListDirection) {
        let ids = websitesNavigationItems()
        guard !ids.isEmpty else { return }
        let currentId = selection ?? viewModel.active?.id
        let nextIndex: Int
        if let currentId, let index = ids.firstIndex(of: currentId) {
            nextIndex = direction == .next ? min(ids.count - 1, index + 1) : max(0, index - 1)
        } else {
            nextIndex = direction == .next ? 0 : ids.count - 1
        }
        let nextId = ids[nextIndex]
        if let item = viewModel.items.first(where: { $0.id == nextId }) {
            open(item: item)
        }
    }

    private func websitesNavigationItems() -> [String] {
        if !searchQuery.trimmed.isEmpty {
            return filteredItems.map { $0.id }
        }
        return pinnedItemsSorted.map { $0.id } + mainItems.map { $0.id }
    }

    @ViewBuilder
    private func websiteListRow(
        item: WebsiteItem,
        index: Int,
        useListStyling: Bool = true,
        allowArchive: Bool = true
    ) -> some View {
        let isSelected = selection == item.id
        let row = WebsiteRow(
            item: item,
            isSelected: isSelected,
            useListStyling: useListStyling,
            faviconBaseUrl: appEnvironment.container.config.r2Endpoint,
            r2FaviconBucket: appEnvironment.container.config.r2FaviconBucket,
            r2FaviconPublicBaseUrl: appEnvironment.container.config.r2FaviconPublicBaseUrl
        )
        .staggeredAppear(index: index, isActive: listAppeared)
        .onTapGesture { open(item: item) }
        .platformContextMenu(items: websiteContextMenuItemsList(for: item))
        .listRowBackground(isSelected ? DesignTokens.Colors.selection : rowBackground)

        #if os(macOS)
        row
        #else
        row
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if allowArchive {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: true) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                    .tint(.blue)
                } else {
                    Button {
                        Task { await viewModel.setArchived(id: item.id, archived: false) }
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                    .tint(.blue)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    deleteTarget = item
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        #endif
    }

    private var pinnedItemsSorted: [WebsiteItem] {
        pinnedItems.sorted { lhs, rhs in
            let leftOrder = lhs.pinnedOrder ?? Int.max
            let rightOrder = rhs.pinnedOrder ?? Int.max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            let leftDate = DateParsing.parseISO8601(lhs.updatedAt) ?? .distantPast
            let rightDate = DateParsing.parseISO8601(rhs.updatedAt) ?? .distantPast
            return leftDate > rightDate
        }
    }

    private var pinnedItems: [WebsiteItem] {
        viewModel.items.filter { $0.pinned && !$0.archived }
    }

    private var mainItems: [WebsiteItem] {
        viewModel.items.filter { !$0.pinned && !$0.archived }
    }

    private var archivedItems: [WebsiteItem] {
        viewModel.items.filter { $0.archived }
    }

    private var archivedEmptyStateText: String {
        if let count = viewModel.archivedSummary?.count {
            if count == 0 {
                return "No archived websites"
            }
        }
        if appEnvironment.isOffline || !appEnvironment.isNetworkAvailable {
            return "Archived websites are available when you're online."
        }
        return "No archived websites"
    }

    private var filteredItems: [WebsiteItem] {
        let needle = searchQuery.trimmed.lowercased()
        guard !needle.isEmpty else { return viewModel.items }
        return viewModel.items.filter { item in
            item.title.lowercased().contains(needle) ||
            item.domain.lowercased().contains(needle) ||
            item.url.lowercased().contains(needle)
        }
    }

    private var panelBackground: Color {
        DesignTokens.Colors.sidebar
    }

    private var rowBackground: Color {
        #if os(macOS)
        return DesignTokens.Colors.sidebar
        #else
        return DesignTokens.Colors.background
        #endif
    }

    private var websitesArchiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Divider()
                .overlay(DesignTokens.Colors.border)
                .padding(.bottom, DesignTokens.Spacing.xs)
            DisclosureGroup(
                isExpanded: $isArchiveExpanded,
                content: {
                    if isArchiveLoading && archivedItems.isEmpty {
                        archiveLoadingRow(message: "Loading archived websites...")
                    }
                    if archivedItems.isEmpty {
                        Text(archivedEmptyStateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                                    websiteListRow(item: item, index: index, useListStyling: false, allowArchive: false)
                                }
                            }
                        }
                        .frame(maxHeight: 650)
                    }
                },
                label: {
                    archiveLabel
                }
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .background(panelBackground)
    }

    private var isArchiveLoading: Bool {
        isArchiveExpanded && viewModel.isLoadingArchived
    }

    @ViewBuilder
    private func archiveLoadingRow(message: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var archiveLabel: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Label("Archive", systemImage: "archivebox")
                .font(.subheadline)
            if isArchiveLoading, !archivedItems.isEmpty {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var isSaveErrorPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    saveErrorMessage = nil
                }
            }
        )
    }

    private var isDeleteAlertPresented: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { newValue in
                if !newValue {
                    deleteTarget = nil
                }
            }
        )
    }

    private func saveWebsite() {
        let raw = newWebsiteUrl.trimmed
        guard let normalized = WebsiteURLValidator.normalizedCandidate(raw) else {
            saveErrorMessage = "Enter a valid URL."
            return
        }
        newWebsiteUrl = ""
        isNewWebsitePresented = false
        Task {
            let saved = await viewModel.saveWebsite(url: normalized.absoluteString)
            if saved {
                appEnvironment.notesViewModel.clearSelection()
                appEnvironment.ingestionViewModel.clearSelection()
            } else {
                saveErrorMessage = viewModel.saveErrorMessage ?? "Failed to save website. Please try again."
            }
        }
    }
}
