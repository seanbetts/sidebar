import SwiftUI
import sideBarShared
#if os(iOS)
import UIKit
#endif

public struct SkillsStorePanel: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        SkillsStorePanelView(viewModel: environment.settingsViewModel)
    }
}

private struct SkillsStorePanelView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var hasLoaded = false
    @State private var selectedCategory: String?
    @FocusState private var isSearchFocused: Bool
    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoadingSkills && storeSkills.isEmpty {
                SidebarListSkeleton(rowCount: 8, showSubtitle: true)
            } else if let error = viewModel.skillsError {
                SidebarPanelPlaceholder(
                    title: "Unable to load Skills Store",
                    subtitle: error,
                    actionTitle: "Retry",
                    style: .error
                ) {
                    Task { await viewModel.loadSkills() }
                }
            } else if filteredSkills.isEmpty {
                SidebarPanelPlaceholder(
                    title: "No store skills found",
                    subtitle: searchQuery.trimmed.isEmpty ? "Try another category." : "Try a different search."
                )
            } else {
                listView
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            if !hasLoaded {
                hasLoaded = true
                Task {
                    if viewModel.settings == nil {
                        await viewModel.load()
                    }
                    await viewModel.loadSkills()
                    ensureDefaultSelection()
                }
            } else {
                ensureDefaultSelection()
            }
        }
        .onChange(of: filteredSkills.map(\.id)) { _, _ in
            ensureDefaultSelection()
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .skillsStore else { return }
            switch event.action {
            case .focusSearch:
                isSearchFocused = true
            default:
                break
            }
        }
    }

    private var header: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            PanelHeader(title: "Skills Store") {
                if isCompact {
                    SettingsAvatarButton()
                }
            }
            SearchField(
                text: $searchQuery,
                placeholder: "Search store skills",
                isFocused: $isSearchFocused
            )
            .padding(.horizontal, DesignTokens.Spacing.md)

            categoryFilter
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.sm)
        }
        .frame(minHeight: LayoutMetrics.panelHeaderMinHeight)
        .background(panelHeaderBackground(colorScheme))
    }

    @ViewBuilder
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                filterChip(title: "All", category: nil)
                ForEach(storeCategories, id: \.self) { category in
                    filterChip(title: category, category: category)
                }
            }
        }
    }

    private func filterChip(title: String, category: String?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        isSelected
                            ? Color.accentColor.opacity(0.18)
                            : DesignTokens.Colors.surface
                    )
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var listView: some View {
        List(filteredSkills, id: \.id) { skill in
            Button {
                environment.skillsStoreSelectedSkillId = skill.id
            } label: {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "storefront")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(viewModel.displayName(for: skill))
                                .font(DesignTokens.Typography.subheadlineSemibold)
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                            if isInstalled(skill) {
                                Text("Installed")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.Colors.success)
                            }
                        }
                        Text(viewModel.displayDescription(for: skill))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(
                DesignTokens.Colors.sidebarRowBackground(
                    isSelected: environment.skillsStoreSelectedSkillId == skill.id
                )
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DesignTokens.Colors.sidebar)
    }

    private var storeSkills: [SkillItem] {
        SkillsStoreLogic.storeSkills(from: viewModel.skills)
    }

    private var storeCategories: [String] {
        SkillsStoreLogic.categories(from: storeSkills)
    }

    private var filteredSkills: [SkillItem] {
        SkillsStoreLogic.filteredStoreSkills(
            storeSkills,
            selectedCategory: selectedCategory,
            searchQuery: searchQuery
        ) { skill in
            [
                viewModel.displayName(for: skill),
                viewModel.displayDescription(for: skill),
                skill.category
            ].joined(separator: " ")
        }
    }

    private func ensureDefaultSelection() {
        environment.skillsStoreSelectedSkillId = SkillsStoreLogic.resolvedSelection(
            currentSelection: environment.skillsStoreSelectedSkillId,
            filteredSkills: filteredSkills
        )
    }

    private func isInstalled(_ skill: SkillItem) -> Bool {
        viewModel.settings?.installedStoreSkills.contains(skill.id) ?? false
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        horizontalSizeClass == .compact
        #endif
    }
}
