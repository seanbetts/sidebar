import SwiftUI
import MarkdownUI

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
    @State private var scrollWidth: CGFloat = 0
    private let contentMaxWidth: CGFloat = 800
    private let contentHorizontalPadding: CGFloat = 20
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
        #if os(iOS) && canImport(SafariServices)
        .sheet(isPresented: safariBinding) {
            if let safariURL {
                SafariView(url: safariURL)
            }
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
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
                let blocks = MarkdownRendering.splitWebsiteContent(stripFrontmatter(website.content))
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .markdown(let text):
                            SideBarMarkdown(text: text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .gallery(let gallery):
                            WebsiteGalleryView(
                                gallery: gallery,
                                availableWidth: galleryWidth
                            )
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(contentHorizontalPadding)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ContentWidthPreferenceKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ContentWidthPreferenceKey.self) { width in
                if width > 0, scrollWidth != width {
                    scrollWidth = width
                }
            }
        } else if viewModel.isLoadingDetail {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.selectedWebsiteId != nil {
            PlaceholderView(title: error)
        } else {
            PlaceholderView(title: "Select a website")
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

    private func stripFrontmatter(_ content: String) -> String {
        let marker = "---"
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(marker) else { return content }
        let parts = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = parts.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == marker else {
            return content
        }
        var endIndex: Int? = nil
        for (index, line) in parts.enumerated().dropFirst() {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == marker {
                endIndex = index
                break
            }
        }
        guard let endIndex else { return content }
        let body = parts.dropFirst(endIndex + 1).joined(separator: "\n")
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private var galleryWidth: CGFloat {
        let available = scrollWidth - (contentHorizontalPadding * 2)
        if available > 0 {
            return min(contentMaxWidth, available)
        }
        return contentMaxWidth
    }
}

private struct WebsiteGalleryView: View {
    let gallery: MarkdownRendering.WebsiteGallery
    let availableWidth: CGFloat
    private let gridSpacing: CGFloat = 12
    private let minImageWidth: CGFloat = 150
    private let maxImageSize = CGSize(width: 450, height: 450)

    var body: some View {
        VStack(alignment: .center, spacing: gridSpacing) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: gridSpacing) {
                    ForEach(rows[rowIndex], id: \.self) { urlString in
                        GalleryImageView(
                            urlString: urlString,
                            maxSize: CGSize(width: imageWidth, height: maxImageSize.height)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if let caption = gallery.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var columns: Int {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let count = Int((effectiveWidth + gridSpacing) / (minImageWidth + gridSpacing))
        return max(1, count)
    }

    private var imageWidth: CGFloat {
        let effectiveWidth = max(availableWidth, minImageWidth)
        let totalSpacing = gridSpacing * CGFloat(max(columns - 1, 0))
        let columnWidth = (effectiveWidth - totalSpacing) / CGFloat(columns)
        return min(columnWidth, maxImageSize.width)
    }

    private var rows: [[String]] {
        chunked(gallery.imageUrls, size: columns)
    }

    private func chunked(_ items: [String], size: Int) -> [[String]] {
        guard size > 0 else { return [items] }
        var chunks: [[String]] = []
        var index = 0
        while index < items.count {
            let end = min(index + size, items.count)
            chunks.append(Array(items[index..<end]))
            index = end
        }
        return chunks
    }
}

private struct GalleryImageView: View {
    let urlString: String
    let maxSize: CGSize

    var body: some View {
        if let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                case .failure:
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(.secondary)
                case .empty:
                    ProgressView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
