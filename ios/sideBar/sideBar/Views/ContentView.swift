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
    @State private var selection: AppSection? = .chat

    public init() {
    }

    public var body: some View {
        if let configError = environment.configError {
            ConfigErrorView(error: configError)
        } else if !environment.isAuthenticated {
            LoginView()
        } else {
        // TODO: Replace with platform-specific navigation (tab on iPhone, split on iPad/macOS).
            NavigationSplitView {
                List(AppSection.allCases, selection: $selection) { section in
                    Text(section.title)
                }
            } detail: {
                SectionDetailView(section: selection)
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
            .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch environment.themeManager.mode {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
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
