import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

// MARK: - FilesPanel

public struct FilesPanel: View {
    @EnvironmentObject var environment: AppEnvironment
    @StateObject private var pinnedReorderState = FilesPanelPinnedReorderState()
    private let showsHeader: Bool

    public init(showsHeader: Bool = true) {
        self.showsHeader = showsHeader
    }

    public var body: some View {
        FilesPanelView(
            viewModel: environment.ingestionViewModel,
            showsHeader: showsHeader,
            pinnedReorderState: pinnedReorderState
        )
    }
}
struct FilesPanelView: View {
    static let actionControlChromeStyle: HeaderActionControlChromeStyle = .glass

    @EnvironmentObject var appEnvironment: AppEnvironment
    @ObservedObject var viewModel: IngestionViewModel
    let showsHeader: Bool
    @State var pinnedReorderNetworkAvailabilityOverride: Bool?
    @State var pinnedReorderAutoExitDelayOverride: TimeInterval?
    let pinnedReorderState: FilesPanelPinnedReorderState
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var expandedCategories: Set<String> = []
    @State var listAppeared = false
    @State var isDeleteAlertPresented = false
    @State var deleteTarget: IngestionListItem?
    @State var pinTarget: IngestionListItem?
    @State var isFileImporterPresented = false
    @State var isYouTubeAlertPresented = false
    @State var newYouTubeUrl: String = ""
    @State var knownFileIds: Set<String> = []
    @State var hasKnownFileIdsBaseline = false
    @State var renameTarget: IngestionListItem?
    @State var renameValue: String = ""
    @State var isRenameSheetPresented = false
    @FocusState var isSearchFocused: Bool

    @MainActor
    init(
        viewModel: IngestionViewModel,
        showsHeader: Bool,
        pinnedReorderState: FilesPanelPinnedReorderState? = nil,
        pinnedReorderNetworkAvailability: Bool? = nil,
        pinnedReorderAutoExitDelay: TimeInterval? = nil
    ) {
        self.viewModel = viewModel
        self.showsHeader = showsHeader
        self.pinnedReorderState = pinnedReorderState ?? FilesPanelPinnedReorderState()
        _pinnedReorderNetworkAvailabilityOverride = State(
            initialValue: pinnedReorderNetworkAvailability
        )
        _pinnedReorderAutoExitDelayOverride = State(
            initialValue: pinnedReorderAutoExitDelay
        )
    }

    var body: some View {
        content
    }
}

extension FilesPanelView {
    var content: some View {
        let base = mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(panelBackground)
            .frame(maxHeight: .infinity)
            .deleteConfirmationAlert(
                title: deleteDialogTitle,
                isPresented: $isDeleteAlertPresented,
                message: "This will remove the file and cannot be undone.",
                onConfirm: confirmDelete,
                onCancel: clearDeleteTarget
            )
            .sheet(
                isPresented: $isRenameSheetPresented,
                onDismiss: clearRenameTarget,
                content: {
                    renameSheet()
                        .phoneSheetGrabBarVisible()
                }
            )
        return base
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: IngestionUploadPolicy.supportedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
            .alert("Add YouTube video", isPresented: $isYouTubeAlertPresented) {
                TextField("youtube.com", text: $newYouTubeUrl)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
                    .onSubmit {
                        addYouTube()
                    }
                Button(viewModel.isIngestingYouTube ? "Adding..." : "Add") {
                    addYouTube()
                }
                .disabled(viewModel.isIngestingYouTube || newYouTubeUrl.trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {
                    newYouTubeUrl = ""
                }
            }
            .onAppear {
                initializeExpandedCategoriesIfNeeded()
                initializeKnownFileIdsBaselineIfNeeded()
            }
            .onChange(of: viewModel.isLoading) { _, _ in
                initializeKnownFileIdsBaselineIfNeeded()
            }
            .onChange(of: categoriesWithItems) { _, _ in
                initializeExpandedCategoriesIfNeeded()
            }
            .onChange(of: viewModel.itemsVersion) { _, _ in
                initializeKnownFileIdsBaselineIfNeeded()
                if FilesPanelExpansionPolicy.shouldAutoExpandVideo(
                    hasBaseline: hasKnownFileIdsBaseline,
                    previousKnownFileIds: knownFileIds,
                    items: viewModel.items
                ) {
                    expandedCategories.insert("video")
                }
                knownFileIds = FilesPanelExpansionPolicy.currentFileIds(from: viewModel.items)
            }
            .onReceive(appEnvironment.navigation.$shortcutActionEvent) { event in
                guard let event, event.section == .files else { return }
                switch event.action {
                case .focusSearch:
                    isSearchFocused = true
                case .newItem:
                    isFileImporterPresented = true
                case .addYouTubeVideo:
                    newYouTubeUrl = ""
                    isYouTubeAlertPresented = true
                case .navigateList(let direction):
                    navigateFilesList(direction: direction)
                default:
                    break
                }
            }
    }

    var mainContent: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header
            }
            switch listPresentationState {
            case .loading:
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            case .retry(let message):
                SidebarPanelPlaceholder(
                    title: "Unable to load files",
                    subtitle: message,
                    actionTitle: "Retry",
                    style: .error
                ) {
                    Task { await viewModel.load() }
                }
            case .search:
                let emptyState = EmptyStateContent.noResults()
                EmptyStateView(
                    title: emptyState.title,
                    subtitle: emptyState.subtitle,
                    systemImage: emptyState.systemImage
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                let emptyState = EmptyStateContent.noContentYet(
                    title: "No files yet",
                    subtitle: "Upload or create a file to get started.",
                    systemImage: "folder"
                )
                EmptyStateView(
                    title: emptyState.title,
                    subtitle: emptyState.subtitle,
                    systemImage: emptyState.systemImage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .content:
                filesListView
            }
        }
    }

    var header: some View {
        let showsInlineSearch = ContentView.shouldShowCompactPhoneInlineSearch(
            isCompact: isCompact,
            isPhoneIdiom: isPhone
        )

        return VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(
                title: "Files",
                minimumContentHeight: HeaderActionControlMetrics.chromeHeight
            ) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if !isCompactPhone {
                        HeaderActionButton(
                            systemName: "play.rectangle",
                            accessibilityLabel: "Add YouTube video",
                            action: {
                            newYouTubeUrl = ""
                            isYouTubeAlertPresented = true
                        },
                            chromeStyle: Self.actionControlChromeStyle
                        )
                        HeaderActionButton(
                            systemName: "plus",
                            accessibilityLabel: "Add file",
                            action: {
                            isFileImporterPresented = true
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
                    placeholder: "Search files",
                    isFocused: $isSearchFocused
                )
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.bottom, DesignTokens.Spacing.sm)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: LayoutMetrics.searchablePanelHeaderMinHeight(showsInlineSearch: showsInlineSearch),
            alignment: .top
        )
        .sidebarPanelHeaderBackground(showsInlineSearch: showsInlineSearch)
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var isCompactPhone: Bool {
        isCompact && isPhone
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var filesListView: some View {
        filesPanelList {
            if !viewModel.panelSearchQuery.trimmed.isEmpty {
                ForEach(searchResults, id: \.file.id) { item in
                    let index = staggerIndex(for: item.file.id)
                    let isSelected = viewModel.selectedFileId == item.file.id
                    let row = FilesIngestionRow(
                        item: item,
                        isSelected: isSelected,
                        onSelect: fileRowPrimaryAction(for: item),
                        onPinToggle: pinAction(for: item),
                        onDelete: deleteAction(for: item)
                    )
                    .platformContextMenu(items: fileContextMenuItemsList(for: item))
                    if isFolder(item) {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                    } else {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                    }
                }
            } else {
                if !pinnedItems.isEmpty {
                    Section {
                        pinnedFilesSection()
                    } header: {
                        sidebarProminentSectionHeader("Pinned")
                    }
                }

                if !categorizedItems.isEmpty {
                    Section {
                        ForEach(categoryOrder, id: \.self) { category in
                            if let items = categorizedItems[category], !items.isEmpty {
                                let isExpanded = bindingForCategory(category).wrappedValue

                                SelectableRow(
                                    isSelected: false,
                                    primaryAction: {
                                        toggleCategoryExpansion(category)
                                    },
                                    content: {
                                        HStack(spacing: 8) {
                                            Image(systemName: categoryIconName(category))
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20, alignment: .center)
                                            Text(categoryLabels[category] ?? "Files")
                                            Spacer()
                                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                                .appFont(.captionSemibold)
                                                .foregroundStyle(.secondary)
                                        }
                                        .appFont(SidebarTypography.primary)
                                    }
                                )
                                .accessibilityLabel(categoryLabels[category] ?? "Files")
                                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                                if isExpanded {
                                    ForEach(items, id: \.file.id) { item in
                                        let index = staggerIndex(
                                            for: item.file.id,
                                            section: category
                                        )
                                        let row = FilesIngestionRow(
                                            item: item,
                                            isSelected: viewModel.selectedFileId == item.file.id,
                                            nestingLevel: 1,
                                            onSelect: fileRowPrimaryAction(for: item),
                                            onPinToggle: pinAction(for: item),
                                            onDelete: deleteAction(for: item)
                                        )
                                        .platformContextMenu(items: fileContextMenuItemsList(for: item))
                                        if isFolder(item) {
                                            row
                                                .staggeredAppear(
                                                    index: index,
                                                    isActive: listAppeared
                                                )
                                        } else {
                                            row
                                                .staggeredAppear(
                                                    index: index,
                                                    isActive: listAppeared
                                                )
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        sidebarProminentSectionHeader("Files")
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
        .onChange(of: pinnedItems.map { $0.file.id }) { _, newValue in
            handlePinnedSetChanged(newValue)
        }
        .refreshable {
            await appEnvironment.refreshSectionManually(.files)
        }
        .onAppear {
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
    }
}
