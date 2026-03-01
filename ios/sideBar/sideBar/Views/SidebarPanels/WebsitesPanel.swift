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
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var hasLoaded = false
    @State var isArchiveExpanded = false
    @State var selection: String?
    @State var listAppeared = false
    @State var isNewWebsitePresented = false
    @State var newWebsiteUrl: String = ""
    @State var saveErrorMessage: String?
    @State var deleteTarget: WebsiteItem?
    @State var renameTarget: WebsiteItem?
    @State var renameValue: String = ""
    @State var isRenameDialogPresented = false
    @State var exportDocument: MarkdownFileDocument?
    @State var isExporting = false
    @State var exportFilename: String = "website"
    @FocusState var isSearchFocused: Bool

    var body: some View {
        let base = VStack(spacing: 0) {
            header
            content
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
        .deleteConfirmationAlert(
            title: "Delete website",
            isPresented: isDeleteAlertPresented,
            message: "This will remove the website and cannot be undone.",
            onConfirm: {
                guard let item = deleteTarget else { return }
                deleteTarget = nil
                Task { await viewModel.deleteWebsite(id: item.id) }
            },
            onCancel: {
                deleteTarget = nil
            }
        )
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
                    if !isCompactPhone {
                        Button {
                            newWebsiteUrl = ""
                            isNewWebsitePresented = true
                        } label: {
                            Image(systemName: "plus")
                                .appFont(.labelMd)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add website")
                    }
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(
                text: Binding(
                    get: { viewModel.panelSearchQuery },
                    set: { viewModel.panelSearchQuery = $0 }
                ),
                placeholder: "Search websites",
                isFocused: $isSearchFocused
            )
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground())
    }

    @ViewBuilder
    var content: some View {
        if viewModel.isLoading && viewModel.items.isEmpty {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry",
                style: .error
            ) {
                Task { await viewModel.load() }
            }
        } else if !viewModel.panelSearchQuery.trimmed.isEmpty {
            List {
                if !viewModel.pendingWebsites.isEmpty {
                    Section {
                        ForEach(viewModel.pendingWebsites, id: \.id) { pending in
                            pendingWebsiteListRow(pending: pending)
                        }
                    } header: {
                        sidebarProminentSectionHeader("Adding")
                    }
                }
                Section {
                    if filteredItems.isEmpty {
                        SidebarPanelPlaceholder(title: "No results.")
                    } else {
                        ForEach(filteredItems, id: \.id) { item in
                            let index = staggerIndex(for: item.id, section: "search")
                            websiteListRow(item: item, index: index, allowArchive: !item.archived)
                        }
                    }
                } header: {
                    sidebarProminentSectionHeader("Results")
                }
            }
            .sidebarPanelListStyle()
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        } else {
            List {
                if !pinnedItemsSorted.isEmpty || !mainItems.isEmpty || !viewModel.pendingWebsites.isEmpty {
                    if !pinnedItemsSorted.isEmpty {
                        Section {
                            ForEach(pinnedItemsSorted, id: \.id) { item in
                                let index = staggerIndex(for: item.id, section: "pinned")
                                websiteListRow(item: item, index: index, allowArchive: true)
                            }
                        } header: {
                            sidebarProminentSectionHeader("Pinned")
                        }
                    }

                    if !mainItems.isEmpty || !viewModel.pendingWebsites.isEmpty {
                        Section {
                            ForEach(viewModel.pendingWebsites, id: \.id) { pending in
                                pendingWebsiteListRow(pending: pending)
                            }
                            ForEach(mainItems, id: \.id) { item in
                                let index = staggerIndex(for: item.id, section: "main")
                                websiteListRow(item: item, index: index, allowArchive: true)
                            }
                        } header: {
                            sidebarProminentSectionHeader("Websites")
                        }
                    }
                }
                Section {
                    SelectableRow(
                        isSelected: false,
                        insets: EdgeInsets(
                            top: DesignTokens.Spacing.xxl,
                            leading: archiveRowHorizontalInset,
                            bottom: 0,
                            trailing: archiveRowHorizontalInset
                        )
                    ) {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Label("Archive", systemImage: "archivebox")
                                .appFont(SidebarTypography.primary)
                            Spacer()
                            if isArchiveLoading && !archivedItems.isEmpty {
                                LoadingIndicatorView(size: LoadingIndicatorSize.inline)
                            }
                            Image(systemName: isArchiveExpanded ? "chevron.down" : "chevron.right")
                                .appFont(SidebarTypography.secondary)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onTapGesture {
                        isArchiveExpanded.toggle()
                    }

                    if isArchiveExpanded {
                        if showArchiveLoadingPlaceholder {
                            SelectableRow(isSelected: false) {
                                archiveLoadingRow(message: "Loading archive...")
                            }
                        } else if showArchiveEmptyState {
                            SelectableRow(isSelected: false) {
                                Text(archivedEmptyStateText)
                                    .appFont(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(archivedItems, id: \.id) { item in
                                let index = staggerIndex(for: item.id, section: "archived")
                                websiteListRow(item: item, index: index, allowArchive: false)
                            }
                        }
                    }
                }
            }
            .sidebarPanelListStyle()
            .scrollContentBackground(.hidden)
            .background(panelBackground)
            .refreshable {
                await viewModel.load()
            }
        }
    }

    var archiveRowHorizontalInset: CGFloat {
        #if os(macOS)
        return DesignTokens.Spacing.sm
        #else
        return DesignTokens.Spacing.smPlus
        #endif
    }
}
