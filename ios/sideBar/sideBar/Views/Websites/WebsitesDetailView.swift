import SwiftUI
import Combine
import sideBarShared
#if canImport(UIKit)
import UIKit
#endif

struct WebsitesDetailView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @Environment(\.openURL) private var openURL
    @State private var safariURL: URL?
    @Binding var exportDocument: MarkdownFileDocument?
    @Binding var exportFilename: String
    @Binding var isExporting: Bool
    @Binding var isRenameDialogPresented: Bool
    @Binding var renameValue: String
    @Binding var isDeleteAlertPresented: Bool
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.workspaceColumn) private var workspaceColumn
    @AppStorage(AppStorageKeys.workspaceExpanded) private var isWorkspaceExpanded: Bool = false
    #if os(iOS)
    @AppStorage(AppStorageKeys.workspaceExpandedByRotation) private var isWorkspaceExpandedByRotation: Bool = false
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if !isCompact {
                header
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onKeyPress(.escape) {
            guard viewModel.active != nil else { return .ignored }
            viewModel.clearSelection()
            return .handled
        }
        .onReceive(environment.navigation.$shortcutActionEvent) { event in
            guard let event, event.section == .websites else { return }
            switch event.action {
            case .closeItem:
                guard viewModel.active != nil else { return }
                viewModel.clearSelection()
            case .renameItem:
                guard viewModel.active != nil else { return }
                renameValue = displayTitle
                isRenameDialogPresented = true
            case .deleteItem:
                guard viewModel.active != nil else { return }
                isDeleteAlertPresented = true
            case .archiveItem:
                archiveActiveWebsite()
            case .openInBrowser:
                openSource()
            default:
                break
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if isCompact, sourceURL != nil {
                    Button(action: openInDefaultBrowser) {
                        Text(displayTitle)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isCompact, viewModel.active != nil, isPhone {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if shouldShowExpandButton {
                        expandButton
                    }
                    websiteToolbarMenu
                }
            }
        }
        #endif
        #if os(iOS) && canImport(SafariServices)
        .sheet(isPresented: safariBinding) {
            if let safariURL {
                SafariView(url: safariURL)
            }
        }
        #endif
    }
}

extension WebsitesDetailView {
    private var header: some View {
        ContentHeaderRow(
            iconView: headerIcon,
            title: displayTitle,
            subtitle: domainSubtitle,
            titleFont: .subheadline.weight(.semibold),
            titleLineLimit: 1,
            subtitleLineLimit: 1,
            titleSubtitleAxis: .vertical,
            onTitleTap: titleTapAction
        ) {
            if viewModel.active != nil {
                HeaderActionRow {
                    if shouldShowExpandButton {
                        expandButton
                    }
                    websiteActionsMenu
                    closeButton
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(height: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private var content: some View {
        if let website = viewModel.active {
            ScrollView {
                SideBarMarkdownContainer(
                    text: website.content,
                    youtubeTranscriptContext: SideBarYouTubeTranscriptContext(
                        websiteId: website.id,
                        isTranscriptPending: { videoId in
                            viewModel.isTranscriptPending(websiteId: website.id, videoId: videoId)
                        },
                        requestTranscript: { websiteId, url in
                            await viewModel.requestYouTubeTranscript(websiteId: websiteId, url: url)
                        }
                    ),
                    renderingContext: .website
                )
            }
        } else if viewModel.isLoadingDetail || viewModel.pendingWebsite != nil {
            LoadingView(message: viewModel.detailLoadingMessage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.selectedWebsiteId != nil {
            PlaceholderView(
                title: "Unable to load website",
                subtitle: error,
                actionTitle: "Retry"
            ) {
                guard let selectedId = viewModel.selectedWebsiteId else { return }
                Task { await viewModel.loadById(id: selectedId) }
            }
        } else if viewModel.isLoading && viewModel.items.isEmpty {
            LoadingView(message: "Loading websites…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(
                title: "Select a website",
                subtitle: "Choose a website from the sidebar to read it.",
                iconName: "globe"
            )
        }
    }

    var displayTitle: String {
        guard let website = viewModel.active else {
            return "Websites"
        }
        if !website.title.isEmpty {
            return website.title
        }
        return website.url
    }

    private var domainSubtitle: String? {
        guard let website = viewModel.active else {
            return nil
        }
        let domain = website.domain.isEmpty ? website.url : website.domain
        let baseDomain = extractBaseDomain(formatDomain(domain))
        let item = viewModel.items.first { $0.id == website.id }
        if let readingTime = item?.readingTime, !readingTime.isEmpty {
            return "\(baseDomain) | \(readingTime)"
        }
        return baseDomain
    }

    private var subtitleText: String? {
        guard let website = viewModel.active else {
            return nil
        }
        var parts: [String] = []
        let domain = website.domain.isEmpty ? website.url : website.domain
        parts.append(formatDomain(domain))
        if let publishedAt = website.publishedAt,
           let date = DateParsing.parseISO8601(publishedAt) {
            parts.append(Self.publishedDateFormatter.string(from: date))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    private func extractBaseDomain(_ domain: String) -> String {
        let parts = domain.split(separator: ".").map(String.init)
        guard parts.count > 2 else { return domain }
        // Check for two-part TLDs like .co.uk, .org.uk, .com.au
        let secondLevelPrefixes: Set<String> = ["co", "com", "org", "net", "gov", "edu", "ac", "or"]
        if parts.count > 2 {
            let last = parts[parts.count - 1]
            let secondLast = parts[parts.count - 2]
            // If second-to-last is a common prefix and last is a 2-letter country code
            if secondLevelPrefixes.contains(secondLast.lowercased()) && last.count == 2 {
                return parts.suffix(3).joined(separator: ".")
            }
        }
        return parts.suffix(2).joined(separator: ".")
    }

    private var headerIcon: AnyView {
        guard let website = viewModel.active else {
            return AnyView(
                Image(systemName: "globe")
                    .font(DesignTokens.Typography.titleLg)
                    .foregroundStyle(.primary)
            )
        }

        let hasFavicon = (website.faviconR2Key?.isEmpty == false)
            || (website.faviconUrl?.isEmpty == false)
        if hasFavicon {
            let faviconView = FaviconImageView(
                faviconUrl: website.faviconUrl,
                faviconR2Key: website.faviconR2Key,
                r2Endpoint: environment.container.config.r2Endpoint,
                r2FaviconBucket: environment.container.config.r2FaviconBucket,
                r2FaviconPublicBaseUrl: environment.container.config.r2FaviconPublicBaseUrl,
                size: 24,
                placeholderTint: DesignTokens.Colors.textPrimary
            )
            return AnyView(faviconView)
        }
        return AnyView(
            Image(systemName: "globe")
                .font(DesignTokens.Typography.titleLg)
                .foregroundStyle(.primary)
        )
    }

    #if os(iOS)
    var isPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }
    #endif

    private var closeButton: some View {
        HeaderActionButton(
            systemName: "xmark",
            accessibilityLabel: "Close website",
            action: { viewModel.clearSelection() },
            isDisabled: viewModel.active == nil
        )
        .keyboardShortcut(.escape, modifiers: [])
    }

    private var expandButton: some View {
        Button(action: expandWebsiteView) {
            Image(systemName: expandButtonIconName)
                .font(DesignTokens.Typography.labelMd)
                .frame(width: 28, height: 20)
                .imageScale(.medium)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expandButtonLabel)
        .disabled(viewModel.active == nil)
    }

    private var shouldShowExpandButton: Bool {
        guard workspaceColumn == .primary else { return false }
        #if os(iOS)
        return !isPhone
        #else
        return true
        #endif
    }

    var isPinned: Bool {
        viewModel.active?.pinned == true
    }

    var isArchived: Bool {
        viewModel.active?.archived == true
    }

    var pinActionTitle: String {
        isPinned ? "Unpin" : "Pin"
    }

    var pinIconName: String {
        isPinned ? "pin.slash" : "pin"
    }

    var archiveMenuTitle: String {
        isArchived ? "Unarchive" : "Archive"
    }

    var archiveIconName: String {
        isArchived ? "archivebox.fill" : "archivebox"
    }

    var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    func openSource() {
        guard let url = sourceURL else { return }
        #if os(iOS) && canImport(SafariServices)
        safariURL = url
        #else
        openURL(url)
        #endif
    }

    func openInDefaultBrowser() {
        guard let url = sourceURL else { return }
        openURL(url)
    }

    func shareWebsiteURL() {
        guard let url = sourceURL else { return }
        SystemSharePresenter.share(url: url)
    }

    func shareWebsiteText() {
        guard let content = viewModel.active?.content, !content.isEmpty else { return }
        let plainText = MarkdownRendering.plainTextForWebsiteShare(content)
        guard !plainText.isEmpty else { return }
        SystemSharePresenter.share(text: plainText)
    }

    func archiveActiveWebsite() {
        guard let websiteId = viewModel.active?.id else { return }
        Task {
            await viewModel.setArchived(id: websiteId, archived: !isArchived)
        }
    }

    private func expandWebsiteView() {
        #if os(iOS)
        if !isPhone {
            isWorkspaceExpandedByRotation = false
        }
        #endif
        isWorkspaceExpanded.toggle()
    }

    private var expandButtonIconName: String {
        isWorkspaceExpanded ? "arrow.up.right.and.arrow.down.left" : "arrow.down.left.and.arrow.up.right"
    }

    private var expandButtonLabel: String {
        isWorkspaceExpanded ? "Exit expanded mode" : "Expand website"
    }

    private var titleTapAction: (() -> Void)? {
        guard sourceURL != nil else { return nil }
        return { openInDefaultBrowser() }
    }

    func exportWebsite() {
        guard let website = viewModel.active else { return }
        let fallbackName = website.title.isEmpty ? "website" : website.title
        let stripped = MarkdownRendering.stripFrontmatter(website.content)
        guard !stripped.isEmpty else { return }
        exportFilename = "\(fallbackName).md"
        exportDocument = MarkdownFileDocument(text: stripped)
        isExporting = true
    }

    var sourceURL: URL? {
        guard let website = viewModel.active else { return nil }
        let urlString = (website.urlFull?.isEmpty == false) ? website.urlFull : website.url
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    func formatDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }

    private var safariBinding: Binding<Bool> {
        Binding(
            get: { safariURL != nil },
            set: { isPresented in
                if !isPresented {
                    safariURL = nil
                }
            }
        )
    }

    private static let publishedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()
}
