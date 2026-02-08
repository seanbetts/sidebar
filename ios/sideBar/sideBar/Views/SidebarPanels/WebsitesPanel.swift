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
        .onReceive(appEnvironment.navigation.$shortcutActionEvent) { event in
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
    var header: some View {
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
    var content: some View {
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
                            if showArchiveLoadingPlaceholder {
                                archiveLoadingRow(message: "Loading archive...")
                                    .padding(.leading, -DesignTokens.Spacing.sm)
                                    .listRowSeparator(.hidden, edges: .top)
                            } else if showArchiveEmptyState {
                                Text(archivedEmptyStateText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .listRowSeparator(.hidden, edges: .top)
                            } else {
                                ForEach(Array(archivedItems.enumerated()), id: \.element.id) { index, item in
                                    websiteListRow(item: item, index: index, allowArchive: false)
                                        .padding(.leading, -DesignTokens.Spacing.sm)
                                }
                            }
                        },
                        label: {
                            archiveLabel
                        }
                    )
                    .listRowBackground(
                        DesignTokens.Colors.sidebarRowBackground
                            .overlay(alignment: .top) {
                                Rectangle()
                                    .fill(DesignTokens.Colors.border)
                                    .frame(height: 1)
                            }
                    )
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
    var websitesPanelContentWithArchive: some View {
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

    var websitesListView: some View {
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
