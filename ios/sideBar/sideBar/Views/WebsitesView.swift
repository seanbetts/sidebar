import SwiftUI
import MarkdownUI

public struct WebsitesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        WebsitesDetailView(viewModel: environment.websitesViewModel)
    }
}

private struct WebsitesDetailView: View {
    @ObservedObject var viewModel: WebsitesViewModel
    @Environment(\.openURL) private var openURL
    @State private var safariURL: URL? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if canImport(SafariServices)
        .sheet(isPresented: safariBinding) {
            if let safariURL {
                SafariView(url: safariURL)
            }
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let active = viewModel.active {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            await viewModel.setPinned(id: active.id, pinned: !active.pinned)
                        }
                    } label: {
                        Image(systemName: active.pinned ? "pin.slash" : "pin")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(buttonBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 1)
                    )
                    .accessibilityLabel(active.pinned ? "Unpin website" : "Pin website")

                    Button {
                        openSource()
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(buttonBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(buttonBorder, lineWidth: 1)
                    )
                    .accessibilityLabel("Open in Safari")
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let website = viewModel.active {
            ScrollView {
                SideBarMarkdown(text: stripFrontmatter(website.content))
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private func openSource() {
        guard let url = sourceURL else { return }
        #if canImport(SafariServices)
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

    private var buttonBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var buttonBorder: Color {
        #if os(macOS)
        return Color(nsColor: .separatorColor)
        #else
        return Color(uiColor: .separator)
        #endif
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
