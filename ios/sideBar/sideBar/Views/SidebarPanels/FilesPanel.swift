import Foundation
import sideBarShared
import SwiftUI
import UniformTypeIdentifiers

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
    @State var searchQuery: String = ""
    @State var listAppeared = false
    @State var isDeleteAlertPresented = false
    @State var deleteTarget: IngestionListItem?
    @State var pinTarget: IngestionListItem?
    @State var isFileImporterPresented = false
    @State var isYouTubeAlertPresented = false
    @State var newYouTubeUrl: String = ""
    @State var knownFileIds: Set<String> = []
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
            .alert(deleteDialogTitle, isPresented: $isDeleteAlertPresented) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                Button("Cancel", role: .cancel) {
                    clearDeleteTarget()
                }
            } message: {
                Text("This will remove the file and cannot be undone.")
            }
            .sheet(
                isPresented: $isRenameSheetPresented,
                onDismiss: clearRenameTarget,
                content: renameSheet
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
                    Task { await viewModel.load() }
                }
                initializeExpandedCategoriesIfNeeded()
                knownFileIds = Set(viewModel.items.map { $0.file.id })
            }
            .onChange(of: categoriesWithItems) { _, _ in
                initializeExpandedCategoriesIfNeeded()
            }
            .onChange(of: viewModel.items.map { $0.file.id }) { _, newIds in
                let newIdSet = Set(newIds)
                let addedIds = newIdSet.subtracting(knownFileIds)
                if !addedIds.isEmpty {
                    for item in viewModel.items where addedIds.contains(item.file.id) {
                        if item.file.mimeOriginal.lowercased().contains("youtube") {
                            expandedCategories.insert("video")
                            break
                        }
                    }
                }
                knownFileIds = newIdSet
            }
            .onReceive(appEnvironment.navigation.$shortcutActionEvent) { event in
                guard let event, event.section == .files else { return }
                switch event.action {
                case .focusSearch:
                    isSearchFocused = true
                case .newItem:
                    isFileImporterPresented = true
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
                    actionTitle: "Retry"
                ) {
                    Task { await viewModel.load() }
                }
            } else if filteredItems.isEmpty {
                if searchQuery.trimmed.isEmpty {
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
                    Button {
                        newYouTubeUrl = ""
                        isYouTubeAlertPresented = true
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add YouTube video")
                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .font(DesignTokens.Typography.labelMd)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add file")
                    if isCompact {
                        SettingsAvatarButton()
                    }
                }
            }
            SearchField(text: $searchQuery, placeholder: "Search files", isFocused: $isSearchFocused)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    var filesListView: some View {
        List {
            if !searchQuery.trimmed.isEmpty {
                ForEach(Array(searchResults.enumerated()), id: \.element.file.id) { index, item in
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
                        ForEach(Array(pinnedItems.enumerated()), id: \.element.file.id) { index, item in
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
                        ForEach(Array(categoryOrder.enumerated()), id: \.element) { categoryIndex, category in
                            if let items = categorizedItems[category], !items.isEmpty {
                                DisclosureGroup(
                                    isExpanded: bindingForCategory(category)
                                ) {
                                    ForEach(Array(items.enumerated()), id: \.element.file.id) { itemIndex, item in
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
                                                    index: categoryIndex + itemIndex,
                                                    isActive: listAppeared
                                                )
                                        } else {
                                            row
                                                .staggeredAppear(
                                                    index: categoryIndex + itemIndex,
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
                                    .font(.subheadline)
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
