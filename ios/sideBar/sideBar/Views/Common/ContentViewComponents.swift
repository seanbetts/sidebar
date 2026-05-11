import SwiftUI
import sideBarShared

struct PhoneDetailRoute: Identifiable, Hashable {
    let id: String
}

struct SectionDefinition {
    let section: AppSection
    let panelView: () -> AnyView
    let detailView: () -> AnyView
    let phoneSelection: () -> Binding<PhoneDetailRoute?>
}

public struct ConfigErrorView: View {
    public let error: EnvironmentConfigLoadError

    public init(error: EnvironmentConfigLoadError) {
        self.error = error
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Configuration Error")
                .appFont(.titleLg)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Check your SideBar.local.xcconfig values and rebuild.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(DesignTokens.Spacing.xl)
    }
}

struct ReauthenticationRequiredView: View {
    let onSignInAgain: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: DesignTokens.Icon.hero, height: DesignTokens.Icon.hero)
                    .accessibilityHidden(true)
                Text("sideBar")
                    .appFont(.titleLg)
            }
            Text("Sign in again")
                .appFont(.titleLg)
            Text("Your session expired. Sign in again to continue.")
                .appFont(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            Button("Sign in") {
                onSignInAgain()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, DesignTokens.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .background(DesignTokens.Colors.background)
    }
}

enum ActiveAlert: Identifiable, Equatable {
    case biometricUnavailable
    case biometricHint
    case fileReady(ReadyFileNotification)

    var id: String {
        switch self {
        case .biometricUnavailable:
            return "biometricUnavailable"
        case .biometricHint:
            return "biometricHint"
        case .fileReady(let notification):
            return "fileReady-\(notification.id)"
        }
    }
}

struct SignedInContentView<Main: View>: View {
    let showsTopSafeAreaOverlay: Bool
    let topSafeAreaBackground: Color
    let onSignOut: () -> Void
    let onOpenSettings: () -> Void
    let mainView: () -> Main
    let scenePhase: ScenePhase
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if environment.isBiometricUnlockRequired {
                BiometricLockView(
                    onUnlock: {
                        Task {
                            await environment.completeBiometricUnlock()
                        }
                    },
                    onOpenSettings: onOpenSettings,
                    onSignOut: onSignOut,
                    scenePhase: scenePhase
                )
            } else {
                GeometryReader { proxy in
                    mainView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(DesignTokens.Colors.background)
                        .coordinateSpace(name: "appRoot")
                        .overlay(alignment: .top) {
                            if showsTopSafeAreaOverlay {
                                Rectangle()
                                    .fill(topSafeAreaBackground)
                                    .frame(height: proxy.safeAreaInsets.top)
                                    .ignoresSafeArea(edges: .top)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
    }
}

public struct WelcomeEmptyView: View {
    public init() {
    }

    public var body: some View {
        VStack(spacing: 12) {
            LoadingIndicatorView(size: 96, variant: .hero)
            Text("Welcome to sideBar")
                .appFont(.titleMd)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct PlaceholderView: View {
    public let title: String
    public let subtitle: String?
    public let actionTitle: String?
    public let action: (() -> Void)?
    public let iconName: String?

    public init(
        title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        iconName: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
        self.iconName = iconName
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let iconName {
                Image(systemName: iconName)
                    .appFont(.displayLg)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .appFont(.titleLg)
            if let subtitle {
                Text(subtitle)
                    .appFont(.subheading)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

enum DetailOfflineUnavailableResource: Equatable {
    case note
    case website
    case file
    case chat
    case taskList

    var title: String {
        switch self {
        case .note:
            return "This note isn't available offline yet"
        case .website:
            return "This website isn't available offline yet"
        case .file:
            return "This file isn't available offline yet"
        case .chat:
            return "This chat isn't available offline yet"
        case .taskList:
            return "This task list isn't available offline yet"
        }
    }

    var subtitle: String {
        "Open it while online on this device to keep it available here."
    }

    var appSection: AppSection {
        switch self {
        case .note:
            return .notes
        case .website:
            return .websites
        case .file:
            return .files
        case .chat:
            return .chat
        case .taskList:
            return .tasks
        }
    }

    var iconName: String {
        appSection.iconName
    }
}

struct DetailOfflineUnavailablePlaceholder: View {
    let resource: DetailOfflineUnavailableResource

    var body: some View {
        PlaceholderView(
            title: resource.title,
            subtitle: resource.subtitle,
            iconName: resource.iconName
        )
    }
}
