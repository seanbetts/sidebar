import SwiftUI

public enum AppSection: String, CaseIterable, Identifiable {
    case chat
    case notes
    case files
    case ingestion
    case websites
    case memories
    case settings
    case weather
    case places
    case tasks

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct ContentView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var selection: AppSection? = .chat
    @State private var primarySection: AppSection = .chat
    @State private var secondarySection: AppSection = .chat
    @AppStorage(AppStorageKeys.leftPanelExpanded) private var isLeftPanelExpanded: Bool = true
    @State private var isSettingsPresented = false
    @State private var phoneSelection: AppSection = .chat

    public init() {
    }

    public var body: some View {
        if let configError = environment.configError {
            ConfigErrorView(error: configError)
        } else if !environment.isAuthenticated {
            LoginView()
        } else {
            GeometryReader { proxy in
                mainView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(topSafeAreaBackground)
                            .frame(height: proxy.safeAreaInsets.top)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Sign Out") {
                        Task {
                            await environment.container.authSession.signOut()
                            environment.refreshAuthState()
                        }
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                if let newValue {
                    primarySection = newValue
                }
            }
            .onChange(of: phoneSelection) { _, newValue in
                selection = newValue
                primarySection = newValue
            }
            .sheet(isPresented: $isSettingsPresented) {
                SettingsView()
                    .environmentObject(environment)
            }
        }
    }

    @ViewBuilder
    private var mainView: some View {
        #if os(macOS)
        splitView
        #else
        if horizontalSizeClass == .compact {
            compactView
        } else {
            splitView
        }
        #endif
    }

    private var splitView: some View {
        WorkspaceLayout(
            selection: $selection,
            isLeftPanelExpanded: $isLeftPanelExpanded,
            onShowSettings: { isSettingsPresented = true },
            header: {
                SiteHeaderBar(onSwapContent: swapPrimaryAndSecondary)
            }
        ) {
            detailView(for: primarySection)
        } rightSidebar: {
            detailView(for: secondarySection)
        }
    }

    private var compactView: some View {
        TabView(selection: $phoneSelection) {
            ForEach(phoneSections, id: \.self) { section in
                phoneTabView(for: section)
                    .tag(section)
                    .tabItem {
                        Label(section.title, systemImage: phoneIconName(for: section))
                    }
            }
        }
    }

    private func detailView(for section: AppSection?) -> some View {
        SectionDetailView(section: section)
    }

    private func swapPrimaryAndSecondary() {
        let temp = primarySection
        primarySection = secondarySection
        secondarySection = temp
        selection = primarySection
    }

    private func phoneTabView(for section: AppSection) -> some View {
        detailView(for: section)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SiteHeaderBar()
                    Divider()
                }
            }
    }

    private var phoneSections: [AppSection] {
        [.notes, .tasks, .websites, .files, .chat]
    }

    private func phoneIconName(for section: AppSection) -> String {
        switch section {
        case .notes:
            return "text.document"
        case .tasks:
            return "checkmark.square"
        case .websites:
            return "globe"
        case .files:
            return "folder"
        case .chat:
            return "bubble"
        default:
            return "square.grid.2x2"
        }
    }

    private var topSafeAreaBackground: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

}

public struct ConfigErrorView: View {
    public let error: EnvironmentConfigLoadError

    public init(error: EnvironmentConfigLoadError) {
        self.error = error
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Configuration Error")
                .font(.title2)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Check your SideBar.local.xcconfig values and rebuild.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

public struct SectionDetailView: View {
    public let section: AppSection?

    public init(section: AppSection?) {
        self.section = section
    }

    public var body: some View {
        // TODO: Swap placeholders for native views per platform conventions.
        switch section {
        case .chat:
            ChatView()
        case .notes:
            NotesView()
        case .files:
            FilesView()
        case .ingestion:
            IngestionView()
        case .websites:
            WebsitesView()
        case .memories:
            MemoriesView()
        case .settings:
            SettingsView()
        case .weather:
            WeatherView()
        case .places:
            PlacesView()
        case .tasks:
            TasksView()
        case .none:
            PlaceholderView(title: "Select a section")
        }
    }
}

public struct PlaceholderView: View {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        VStack {
            Text(title)
                .font(.title2)
        }
    }
}
