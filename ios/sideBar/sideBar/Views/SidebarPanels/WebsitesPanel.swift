import Foundation
import sideBarShared
import SwiftUI

// MARK: - WebsitesPanel

public struct WebsitesPanel: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @StateObject private var pinnedReorderState = WebsitesPanelPinnedReorderState()

    public init() {
    }

    public var body: some View {
        WebsitesPanelView(
            viewModel: appEnvironment.websitesViewModel,
            pinnedReorderState: pinnedReorderState
        )
    }
}
struct WebsitesPanelView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @ObservedObject var viewModel: WebsitesViewModel
    @EnvironmentObject var appEnvironment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var pinnedReorderNetworkAvailabilityOverride: Bool?
    @State var pinnedReorderAutoExitDelayOverride: TimeInterval?
    let pinnedReorderState: WebsitesPanelPinnedReorderState
    @State var hasLoaded = false
    @State var isInitialLoadPending = false
    @State var isArchiveExpanded = false
    @State var selection: String?
    @State var listAppeared = false
    @State var isArchiveLoadPending = false
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

    @MainActor
    init(
        viewModel: WebsitesViewModel,
        pinnedReorderState: WebsitesPanelPinnedReorderState? = nil,
        pinnedReorderNetworkAvailability: Bool? = nil,
        pinnedReorderAutoExitDelay: TimeInterval? = nil
    ) {
        self.viewModel = viewModel
        self.pinnedReorderState = pinnedReorderState ?? WebsitesPanelPinnedReorderState()
        _pinnedReorderNetworkAvailabilityOverride = State(
            initialValue: pinnedReorderNetworkAvailability
        )
        _pinnedReorderAutoExitDelayOverride = State(
            initialValue: pinnedReorderAutoExitDelay
        )
    }

    static var shouldSubmitWebsiteAlertFromTextField: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    var body: some View {
        let base = VStack(spacing: 0) {
            header
            content
        }
        .sidebarPanelScaffoldBackground()
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                isInitialLoadPending = true
                Task {
                    await viewModel.load()
                    isInitialLoadPending = false
                }
            }
            if selection == nil {
                selection = viewModel.selectedWebsiteId ?? viewModel.active?.id
            }
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.selectedWebsiteId) { _, newValue in
            selection = newValue ?? viewModel.active?.id
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
        .onChange(of: isArchiveExpanded) { _, expanded in
            if expanded {
                isArchiveLoadPending = true
                Task {
                    await viewModel.loadArchived()
                    isArchiveLoadPending = false
                }
            }
        }
        return base
        .alert("Save a website", isPresented: $isNewWebsitePresented) {
            websiteSaveTextField
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
    @ViewBuilder
    var websiteSaveTextField: some View {
        let textField = TextField("example.com", text: $newWebsiteUrl)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .keyboardType(.URL)
            #endif
            .autocorrectionDisabled()
            #if os(iOS)
            .submitLabel(.done)
            #endif

        if Self.shouldSubmitWebsiteAlertFromTextField {
            textField.onSubmit {
                saveWebsite()
            }
        } else {
            textField
        }
    }

    var header: some View {
        let showsInlineSearch = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: isCompact,
            isPhoneIdiom: isCompactPhone
        )

        return VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Websites") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if !isCompactPhone {
                        HeaderActionButton(
                            systemName: "plus",
                            accessibilityLabel: "Add website",
                            action: {
                            newWebsiteUrl = ""
                            isNewWebsitePresented = true
                        },
                            chromeStyle: Self.actionControlChromeStyle
                        )
                    }
                    if isCompact {
                        GlobalAvatarRegionControls()
                    }
                }
            }
            if showsInlineSearch {
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
        }
        .frame(minHeight: LayoutMetrics.searchablePanelHeaderMinHeight(showsInlineSearch: showsInlineSearch))
        .sidebarPanelHeaderBackground(showsInlineSearch: showsInlineSearch)
    }

    @ViewBuilder
    var content: some View {
        if panelState == .loading {
            SidebarListSkeleton(rowCount: 8, showSubtitle: true)
        } else if panelState == .error, let error = viewModel.errorMessage {
            SidebarPanelPlaceholder(
                title: "Unable to load websites",
                subtitle: error,
                actionTitle: "Retry",
                style: .error
            ) {
                Task { await viewModel.load() }
            }
        } else if panelState == .empty {
            EmptyStateView(
                title: "No websites yet",
                subtitle: "Save a link to get started.",
                systemImage: "globe"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(panelBackground)
        } else if panelState == .search {
            websitesPanelList {
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
            .sidebarPanelListStyle(reducesCompactPhoneSectionHeaderGap: isCompactPhone)
            .sidebarCompactPhoneTopPadding(
                LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,
                isCompactPhone: isCompactPhone
            )
            .scrollContentBackground(.hidden)
            .sidebarPanelListBackground()
            .refreshable {
                await viewModel.load()
            }
        } else {
            websitesPanelList {
                if listSectionLayout.contains(.sparseState) {
                    Section {
                        SidebarSparseStateRow(
                            iconName: "globe",
                            title: Self.sparseStateTitle,
                            subtitle: Self.sparseStateSubtitle
                        )
                    }
                }

                if listSectionLayout.contains(.primaryContent) {
                    if !pinnedItemsSorted.isEmpty {
                        Section {
                            pinnedWebsitesSection()
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
                if listSectionLayout.contains(.archive) {
                    Section {
                        SelectableRow(
                            isSelected: false,
                            insets: EdgeInsets(
                                top: DesignTokens.Spacing.xxl,
                                leading: archiveRowHorizontalInset,
                                bottom: 0,
                                trailing: archiveRowHorizontalInset
                            ),
                            primaryAction: {
                                isArchiveExpanded.toggle()
                            },
                            content: {
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
                        )

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
            }
            .sidebarPanelListStyle(reducesCompactPhoneSectionHeaderGap: isCompactPhone)
            .sidebarCompactPhoneTopPadding(
                LayoutMetrics.compactPhoneSectionedPanelTopPaddingAdjustment,
                isCompactPhone: isCompactPhone
            )
            #if os(iOS)
            .environment(\.editMode, .constant(isPinnedReorderEditActive ? .active : .inactive))
            #endif
            .scrollContentBackground(.hidden)
            .sidebarPanelListBackground()
            .onChange(of: pinnedItemsSorted.map(\.id)) { _, newValue in
                handlePinnedSetChanged(newValue)
            }
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
