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

    public init() {
    }

    public var body: some View {
        FilesPanelView(viewModel: environment.ingestionViewModel)
    }
}
struct FilesPanelView: View {
    @EnvironmentObject var appEnvironment: AppEnvironment
    @ObservedObject var viewModel: IngestionViewModel
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.colorScheme) var colorScheme
    @State var hasLoaded = false
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
    @State var isAwaitingInitialLoad = false
    @State var renameTarget: IngestionListItem?
    @State var renameValue: String = ""
    @State var isRenameSheetPresented = false
    @FocusState var isSearchFocused: Bool

    var body: some View {
        content
    }
}

extension FilesPanelView {
    var content: some View {
        let base = mainContent
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
                allowedContentTypes: [.item],
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
                if !hasLoaded {
                    hasLoaded = true
                    isAwaitingInitialLoad = true
                    Task {
                        await viewModel.load()
                        isAwaitingInitialLoad = false
                        initializeKnownFileIdsBaselineIfNeeded()
                    }
                }
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
            header
            if viewModel.isLoading && viewModel.items.isEmpty {
                SidebarListSkeleton(rowCount: 8, showSubtitle: false)
            } else if let message = viewModel.errorMessage {
                SidebarPanelPlaceholder(
                    title: "Unable to load files",
                    subtitle: message,
                    actionTitle: "Retry",
                    style: .error
                ) {
                    Task { await viewModel.load() }
                }
            } else if filteredItems.isEmpty {
                if viewModel.panelSearchQuery.trimmed.isEmpty {
                    SidebarPanelPlaceholder(title: "No files yet.")
                } else {
                    SidebarPanelPlaceholder(title: "No results.")
                }
            } else {
                filesListView
            }
        }
    }

    var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Files") {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    if !isCompactPhone {
                        Button {
                            newYouTubeUrl = ""
                            isYouTubeAlertPresented = true
                        } label: {
                            Image(systemName: "play.rectangle")
                                .appFont(.labelMd)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add YouTube video")
                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Image(systemName: "plus")
                                .appFont(.labelMd)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add file")
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
                placeholder: "Search files",
                isFocused: $isSearchFocused
            )
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground())
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
        List {
            if !viewModel.panelSearchQuery.trimmed.isEmpty {
                ForEach(searchResults, id: \.file.id) { item in
                    let index = staggerIndex(for: item.file.id)
                    let isSelected = viewModel.selectedFileId == item.file.id
                    let row = FilesIngestionRow(
                        item: item,
                        isSelected: isSelected,
                        onPinToggle: pinAction(for: item),
                        onDelete: deleteAction(for: item)
                    )
                    .platformContextMenu(items: fileContextMenuItemsList(for: item))
                    .listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected: isSelected))
                    if isFolder(item) {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                    } else {
                        row
                            .staggeredAppear(index: index, isActive: listAppeared)
                            .onTapGesture { open(item: item) }
                    }
                }
            } else {
                if !pinnedItems.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedItems, id: \.file.id) { item in
                            let index = staggerIndex(for: item.file.id)
                            let isSelected = viewModel.selectedFileId == item.file.id
                            let row = FilesIngestionRow(
                                item: item,
                                isSelected: isSelected,
                                onPinToggle: pinAction(for: item),
                                onDelete: deleteAction(for: item)
                            )
                            .platformContextMenu(items: fileContextMenuItemsList(for: item))
                            .listRowBackground(DesignTokens.Colors.sidebarRowBackground(isSelected: isSelected))
                            if isFolder(item) {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                            } else {
                                row
                                    .staggeredAppear(index: index, isActive: listAppeared)
                                    .onTapGesture { open(item: item) }
                            }
                        }
                    }
                }

                if !categorizedItems.isEmpty {
                    Section("Files") {
                        ForEach(categoryOrder, id: \.self) { category in
                            if let items = categorizedItems[category], !items.isEmpty {
                                DisclosureGroup(
                                    isExpanded: bindingForCategory(category)
                                ) {
                                    ForEach(items, id: \.file.id) { item in
                                        let index = staggerIndex(
                                            for: item.file.id,
                                            section: category
                                        )
                                        let row = FilesIngestionRow(
                                            item: item,
                                            isSelected: viewModel.selectedFileId == item.file.id,
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
                                                .onTapGesture { open(item: item) }
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: categoryIconName(category))
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .center)
                                        Text(categoryLabels[category] ?? "Files")
                                    }
                                    .appFont(.subheadline)
                                }
                                .listRowBackground(DesignTokens.Colors.sidebarRowBackground)
                            }
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
        .onAppear {
            listAppeared = !viewModel.isLoading
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            listAppeared = !isLoading
        }
    }
}
