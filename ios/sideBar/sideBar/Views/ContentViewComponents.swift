import SwiftUI

struct PhoneDetailRoute: Identifiable, Hashable {
    let id: String
}

struct SectionDefinition {
    let section: AppSection
    let panelView: () -> AnyView
    let detailView: () -> AnyView
    let phoneSelection: () -> Binding<PhoneDetailRoute?>
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
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

private enum ActiveAlert: Identifiable, Equatable {
    case biometricUnavailable
    case biometricHint
    case sessionExpiry
    case fileReady(ReadyFileNotification)

    var id: String {
        switch self {
        case .biometricUnavailable:
            return "biometricUnavailable"
        case .biometricHint:
            return "biometricHint"
        case .sessionExpiry:
            return "sessionExpiry"
        case .fileReady(let notification):
            return "fileReady-\(notification.id)"
        }
    }
}

struct SignedInContentView<Main: View>: View {
    let biometricUnlockEnabled: Bool
    @Binding var isBiometricUnlocked: Bool
    let topSafeAreaBackground: Color
    let onSignOut: () -> Void
    let mainView: () -> Main
    let scenePhase: ScenePhase
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Group {
            if biometricUnlockEnabled && !isBiometricUnlocked {
                BiometricLockView(
                    onUnlock: { isBiometricUnlocked = true },
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

public struct WelcomeEmptyView: View {
    public init() {
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .opacity(0.7)
            Text("Welcome to sideBar")
                .font(.title3.weight(.semibold))
            Text("Select a note, website, or file to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.title2)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
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
