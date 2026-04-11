import SwiftUI
import sideBarShared

struct MemoriesSettingsView: View {
    @ObservedObject var viewModel: MemoriesViewModel

    var body: some View {
        MemoriesSettingsDetailView(viewModel: viewModel)
    }
}

struct ShortcutsSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var copied = false

    var body: some View {
        #if os(macOS)
        ScrollView {
            SettingsMacPanelCard {
                SettingsMacSectionIntro(
                    title: "Shortcuts token",
                    message: "Use this token in Apple Shortcuts to authorize quick capture on this account."
                )
                FormField("Token") {
                    Group {
                        if viewModel.shortcutsToken.isEmpty {
                            Text("No token generated yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(viewModel.shortcutsToken)
                                .textSelection(.enabled)
                        }
                    }
                    .appFont(.body)
                    .frame(maxWidth: 360, alignment: .leading)
                }
                FormField("Actions") {
                    HStack(spacing: 12) {
                        Button(copied ? "Copied" : "Copy") {
                            copyToken()
                        }
                        .disabled(viewModel.shortcutsToken.isEmpty)

                        Button(viewModel.isRotatingShortcuts ? "Regenerating..." : "Regenerate") {
                            Task { await viewModel.rotateShortcutsToken() }
                        }
                        .disabled(viewModel.isRotatingShortcuts || viewModel.isLoadingShortcuts)
                    }
                }
                if let error = viewModel.shortcutsError, !error.isEmpty {
                    SettingsMacStatusBanner(message: error, tone: .error)
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        .overlay {
            if viewModel.isLoadingShortcuts && viewModel.shortcutsToken.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
        #else
        Form {
            Section("Shortcuts") {
                Text("Use this token in Apple Shortcuts to authorize quick capture.")
                    .foregroundStyle(.secondary)
                Group {
                    if viewModel.shortcutsToken.isEmpty {
                        Text("No token generated yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(viewModel.shortcutsToken)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .appFont(.body)
                HStack(spacing: 12) {
                    Button(copied ? "Copied" : "Copy") {
                        copyToken()
                    }
                    .disabled(viewModel.shortcutsToken.isEmpty)

                    Button(viewModel.isRotatingShortcuts ? "Regenerating..." : "Regenerate") {
                        Task { await viewModel.rotateShortcutsToken() }
                    }
                    .disabled(viewModel.isRotatingShortcuts || viewModel.isLoadingShortcuts)
                }
                if let error = viewModel.shortcutsError {
                    Text(error)
                        .appFont(.caption)
                        .foregroundStyle(DesignTokens.Colors.error)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .overlay {
            if viewModel.isLoadingShortcuts && viewModel.shortcutsToken.isEmpty {
                LoadingIndicatorView(size: LoadingIndicatorSize.page)
            }
        }
        #endif
    }

    private func copyToken() {
        guard !viewModel.shortcutsToken.isEmpty else { return }
        let token = viewModel.shortcutsToken
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(token, forType: .string)
        #else
        let pasteboard = UIPasteboard.general
        pasteboard.string = token
        #endif
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == token {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == token {
                pasteboard.string = ""
            }
            #endif
        }
    }
}

struct TasksSettingsView: View {
    var body: some View {
        #if os(macOS)
        ScrollView {
            SettingsMacPanelCard {
                SettingsMacSectionIntro(
                    title: "Tasks",
                    message: "Tasks use sideBar's built-in task system and stay in sync with the main workspace."
                )
                SettingsMacStatusBanner(
                    message: "Set up your task lists in sideBar to see them reflected here.",
                    tone: .info
                )
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        #else
        Form {
            Section("Tasks") {
                Text("Tasks sync uses the built-in sideBar task system.")
                    .foregroundStyle(.secondary)
                Text("Set up your tasks in sideBar to see them here.")
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        #endif
    }
}

struct APISettingsView: View {
    let settings: UserSettings?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "API",
                        message: "Core API behavior is managed by your server configuration."
                    )
                    if let userId = settings?.userId {
                        FormField("User ID") {
                            Text(userId)
                                .appFont(.body)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    SettingsMacStatusBanner(
                        message: "API settings are managed by your server configuration.",
                        tone: .info
                    )
                }
#if DEBUG
                SettingsMacPanelCard {
                    SettingsMacSectionIntro(
                        title: "Debug",
                        message: "Internal asset and appearance checks for development builds."
                    )
                    HStack(spacing: 16) {
                        VStack(spacing: 8) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                            Text("AppLogo (system)")
                                .appFont(.caption)
                        }
                        VStack(spacing: 8) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .environment(\.colorScheme, .dark)
                            Text("AppLogo (forced dark)")
                                .appFont(.caption)
                        }
                    }
                    SettingsMacStatusBanner(
                        message: "Color scheme: \(colorScheme == .dark ? "dark" : "light")",
                        tone: .info
                    )
                }
#endif
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(DesignTokens.Colors.settingsBackground)
        #else
        Form {
            Section("API") {
                if let userId = settings?.userId {
                    LabeledContent("User ID", value: userId)
                }
                Text("API settings are managed by your server configuration.")
                    .foregroundStyle(.secondary)
            }
#if DEBUG
            Section("Debug") {
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                        Text("AppLogo (system)")
                            .appFont(.caption)
                    }
                    VStack(spacing: 8) {
                        Image("AppLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .environment(\.colorScheme, .dark)
                        Text("AppLogo (forced dark)")
                            .appFont(.caption)
                    }
                }
                Text("Color scheme: \(colorScheme == .dark ? "dark" : "light")")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
#endif
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        #endif
    }
}
