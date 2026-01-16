import SwiftUI

public struct WebsitesView: View {
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    public init() {
    }

    public var body: some View {
        WebsitesDetailView(viewModel: environment.websitesViewModel)
            #if !os(macOS)
            .navigationTitle(websiteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isCompact {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                        } label: {
                            Image(systemName: "line.3.horizontal")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Website options")
                    }
                }
            }
            #endif
    }

    private var websiteTitle: String {
        #if os(macOS)
        return "Websites"
        #else
        guard horizontalSizeClass == .compact else {
            return "Websites"
        }
        guard let website = environment.websitesViewModel.active else {
            return "Websites"
        }
        return website.title.isEmpty ? website.url : website.title
        #endif
    }

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }
}

private struct WebsitesDetailView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @Environment(\.openURL) private var openURL
    @State private var safariURL: URL? = nil
    @EnvironmentObject private var environment: AppEnvironment
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if environment.isOffline {
                OfflineBanner()
            }
            if !isCompact {
                header
                Divider()
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if os(iOS) && canImport(SafariServices)
        .sheet(isPresented: safariBinding) {
            if let safariURL {
                SafariView(url: safariURL)
            }
        }
        #endif
    }

    private var header: some View {
        ContentHeaderRow(
            iconName: "globe",
            title: displayTitle,
            subtitle: subtitleText,
            titleLineLimit: 2,
            subtitleLineLimit: 2,
            alignment: .firstTextBaseline,
            titleSubtitleAlignment: .firstTextBaseline
        ) {
            Button {
            } label: {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .font(.system(size: 16, weight: .semibold))
            .imageScale(.medium)
            .accessibilityLabel("Website options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(minHeight: LayoutMetrics.contentHeaderMinHeight)
    }

    @ViewBuilder
    private var content: some View {
        if let website = viewModel.active {
            ScrollView {
                SideBarMarkdownContainer(text: website.content)
            }
        } else if viewModel.isLoadingDetail {
            LoadingView(message: "Loading website…")
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

    private var displayTitle: String {
        guard let website = viewModel.active else {
            return "Websites"
        }
        if !website.title.isEmpty {
            return website.title
        }
        return website.url
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

    private var isCompact: Bool {
        #if os(macOS)
        return false
        #else
        return horizontalSizeClass == .compact
        #endif
    }

    private func openSource() {
        guard let url = sourceURL else { return }
        #if os(iOS) && canImport(SafariServices)
        safariURL = url
        #else
        openURL(url)
        #endif
    }

    private var sourceURL: URL? {
        guard let website = viewModel.active else { return nil }
        let urlString = (website.urlFull?.isEmpty == false) ? website.urlFull : website.url
        guard let urlString else { return nil }
        return URL(string: urlString)
    }

    private func formatDomain(_ domain: String) -> String {
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
