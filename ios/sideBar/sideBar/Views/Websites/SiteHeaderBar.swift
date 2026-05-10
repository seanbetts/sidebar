import SwiftUI
import sideBarShared
import Combine
#if os(iOS)
import UIKit
#endif

// MARK: - SiteHeaderBar

public struct SiteHeaderBar: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @AppStorage(AppStorageKeys.weatherUsesFahrenheit) private var weatherUsesFahrenheit = false
    @StateObject private var headerStatusController = HeaderStatusController()
    @State private var isScratchpadPresented = false
    private let onSwapContent: (() -> Void)?
    private let onToggleSidebar: (() -> Void)?
    private let onShowSettings: (() -> Void)?
    private let isLeftPanelExpanded: Bool
    private let shouldAnimateSidebar: Bool

    public init(
        onSwapContent: (() -> Void)? = nil,
        onToggleSidebar: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil,
        isLeftPanelExpanded: Bool = true,
        shouldAnimateSidebar: Bool = true
    ) {
        self.onSwapContent = onSwapContent
        self.onToggleSidebar = onToggleSidebar
        self.onShowSettings = onShowSettings
        self.isLeftPanelExpanded = isLeftPanelExpanded
        self.shouldAnimateSidebar = shouldAnimateSidebar
    }

    public var body: some View {
        Group {
            if isCompact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        brandView
                        Spacer()
                        trailingControls
                    }
                }
            } else {
                HStack(spacing: 16) {
                    brandView
                    Spacer()
                    trailingControls
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .frame(minHeight: LayoutMetrics.appHeaderMinHeight)
        .background(barBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event,
                  event.action == .openScratchpad,
                  scratchpadPresentationStyle == .anchoredPopover else { return }
            isScratchpadPresented = true
        }
        .onReceive(
            Publishers.CombineLatest4(
                environment.writeQueue.$failedHeaderRows,
                environment.writeQueue.$isExecutingWrite,
                environment.writeQueue.$pendingCount,
                environment.writeQueue.$failedCount
            )
        ) { _ in
            refreshSyncHeaderStatus()
        }
        .onChange(of: environment.authState) { _, _ in
            refreshSessionHeaderStatus()
        }
        .onReceive(
            Publishers.CombineLatest(
                environment.ingestionViewModel.$itemsVersion,
                environment.ingestionViewModel.$latestHeaderReadyEvent
            )
        ) { _ in
            refreshIngestionHeaderStatus()
        }
        .onReceive(environment.chatViewModel.$activeTool) { _ in
            refreshToolHeaderStatus()
        }
        .onAppear {
            refreshSessionHeaderStatus()
            refreshSyncHeaderStatus()
            refreshIngestionHeaderStatus()
            refreshToolHeaderStatus()
        }
    }

    private var brandView: some View {
        HStack(spacing: 10) {
            if isCompact || isLeftPanelExpanded {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .transition(.scale.combined(with: .opacity))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 4, height: 35)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .opacity(0.9)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("sideBar")
                    .appFont(.subheading)
                    .fontWeight(.bold)
                Text("WORKSPACE")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            headerStatusCluster
        }
        .animation(shouldAnimateSidebar ? .smooth(duration: 0.3) : nil, value: isLeftPanelExpanded)
        .contentShape(Rectangle())
        .onTapGesture {
            if isCompact {
                onToggleSidebar?()
            }
        }
        .accessibilityLabel(isCompact ? "Show sidebar" : "sideBar")
        .accessibilityAddTraits(isCompact ? .isButton : [])
    }

    private var trailingControls: some View {
        HStack(alignment: .center, spacing: 12) {
            if !isCompact {
                if environment.isOffline || !environment.isServerReachable {
                    OfflineBanner()
                        .offset(x: -8)
                }
                VStack(alignment: .trailing, spacing: 4) {
                    HeaderInfoItem(icon: "cloud.sun", text: weatherText)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(locationText)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, DesignTokens.Spacing.smPlus)
                desktopTrailingActionControls
            }

            if isCompact {
                compactTrailingActionControls
            } else {
                EmptyView()
            }
        }
    }

    private var barBackground: Color {
        DesignTokens.Colors.background
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private var scratchpadPresentationStyle: ScratchpadPresentationStyle {
        WorkspaceBehaviorPolicy.scratchpadPresentationStyle(isPhoneIdiom: isPhoneIdiom)
    }

    private var isPhoneIdiom: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var weatherText: String {
        if environment.weatherViewModel.isLoading {
            return "Loading..."
        }
        if let weather = environment.weatherViewModel.weather {
            return temperatureText(weather.temperatureC)
        }
        return "Weather"
    }

    private var locationText: String {
        let currentLocation = environment.currentLocationViewModel.currentLocationLabel?.trimmed ?? ""
        if !currentLocation.isEmpty {
            return formattedLocation(currentLocation)
        }
        let location = environment.settingsViewModel.settings?.location?.trimmed ?? ""
        return location.isEmpty ? "Set location" : formattedLocation(location)
    }

    private func temperatureText(_ celsius: Double) -> String {
        if weatherUsesFahrenheit {
            let fahrenheit = Int(round(celsius * 9 / 5 + 32))
            return "\(fahrenheit)°F"
        }
        let roundedCelsius = Int(round(celsius))
        return "\(roundedCelsius)°C"
    }

    private func formattedLocation(_ value: String) -> String {
        let parts = value
            .split(separator: ",")
            .map { $0.trimmed }
        guard let first = parts.first else { return value }
        guard let last = parts.last, last != first else { return String(first) }
        let locale = Locale.current
        let city = first.uppercased(with: locale)
        let country = last.uppercased(with: locale)
        return "\(city), \(country)"
    }

    private var headerStatusCluster: some View {
        HStack(spacing: DesignTokens.Spacing.xxsPlus) {
            ForEach(headerStatusController.visiblePills) { pill in
                HeaderStatusPillButton(pill: pill) { row, action in
                    await performHeaderAction(for: pill, row: row, action: action)
                }
            }
        }
        .padding(.leading, headerStatusController.visiblePills.isEmpty ? 0 : DesignTokens.Spacing.xxsPlus)
    }

    static var desktopTrailingActionChrome: GlassChrome.Kind {
        desktopTrailingActionChromeStyle.kind
    }

    static var desktopTrailingActionChromeStyle: HeaderActionControlChromeStyle {
        .glass
    }

    static func usesGroupedGlass(forCompact: Bool) -> Bool {
        false
    }

    @ViewBuilder
    private var desktopTrailingActionControls: some View {
        desktopTrailingActionButtons
    }

    private var desktopTrailingActionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            HeaderActionButton(
                systemName: "arrow.left.arrow.right",
                accessibilityLabel: "Swap panels",
                action: { onSwapContent?() },
                isDisabled: onSwapContent == nil,
                chromeStyle: Self.desktopTrailingActionChromeStyle
            )

            HeaderActionButton(
                systemName: "square.and.pencil",
                accessibilityLabel: "Scratchpad",
                action: { isScratchpadPresented.toggle() },
                chromeStyle: Self.desktopTrailingActionChromeStyle
            )
            .popover(
                isPresented: $isScratchpadPresented,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .top
            ) {
                ScratchpadPopoverSurface(
                    api: environment.container.scratchpadAPI,
                    cache: environment.container.cacheClient,
                    scratchpadStore: environment.scratchpadStore
                )
                .presentationCompactAdaptation(.sheet)
            }
        }
    }

    private var compactTrailingActionControls: some View {
        GlobalAvatarRegionControls()
    }

    private func refreshSyncHeaderStatus() {
        headerStatusController.applySync(snapshot: environment.writeQueue.headerStatusSnapshot)
    }

    private func refreshSessionHeaderStatus() {
        headerStatusController.applySession(snapshot: sessionHeaderStatusSnapshot)
    }

    private func refreshIngestionHeaderStatus() {
        headerStatusController.applyIngestion(snapshot: environment.ingestionViewModel.headerStatusSnapshot)
    }

    private func refreshToolHeaderStatus() {
        headerStatusController.applyTool(snapshot: toolHeaderStatusSnapshot)
    }

    private var sessionHeaderStatusSnapshot: HeaderSessionStatusSnapshot? {
        switch environment.authState {
        case .staleRecoverable:
            return .syncPaused
        case .active, .reauthenticationRequired, .signedOut:
            return nil
        }
    }

    private var toolHeaderStatusSnapshot: HeaderToolStatusSnapshot? {
        guard let activeTool = environment.chatViewModel.activeTool else {
            return nil
        }
        return .active(name: activeTool.name, status: activeTool.status)
    }

    private func performHeaderAction(
        for pill: HeaderStatusPillModel,
        row: HeaderStatusRowModel,
        action: HeaderStatusActionModel
    ) async -> HeaderStatusRowActionResult {
        switch pill.kind {
        case .session:
            return .failed("This status updates automatically.")
        case .sync:
            return await performSyncHeaderAction(row: row, action: action)
        case .ingestion:
            return await performIngestionHeaderAction(row: row, action: action)
        case .tool:
            return .failed("This status updates automatically.")
        }
    }

    private func performSyncHeaderAction(
        row: HeaderStatusRowModel,
        action: HeaderStatusActionModel
    ) async -> HeaderStatusRowActionResult {
        guard let writeID = UUID(uuidString: row.id) else {
            return .failed("This sync item is no longer available.")
        }

        do {
            switch action.id {
            case "retry":
                try await environment.writeQueue.retryWrite(id: writeID)
            case "cancel":
                try await environment.writeQueue.cancelWrite(id: writeID)
            default:
                return .failed("This sync action isn't supported.")
            }
            return .resolved
        } catch {
            refreshSyncHeaderStatus()
            return .failed("Failed to \(action.title.lowercased()).")
        }
    }

    private func performIngestionHeaderAction(
        row: HeaderStatusRowModel,
        action: HeaderStatusActionModel
    ) async -> HeaderStatusRowActionResult {
        guard action.id == "cancel" else {
            return .failed("This upload action isn't supported.")
        }

        do {
            try await environment.ingestionViewModel.cancelHeaderIngestion(fileId: row.id)
            return .resolved
        } catch {
            refreshIngestionHeaderStatus()
            return .failed(error.localizedDescription)
        }
    }
}

private struct HeaderInfoItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .appFont(.subheading)
        }
    }
}
