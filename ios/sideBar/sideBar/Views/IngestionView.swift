import SwiftUI

public struct IngestionView: View {
    @EnvironmentObject private var environment: AppEnvironment

    public init() {
    }

    public var body: some View {
        IngestionSplitView(viewModel: environment.ingestionViewModel)
    }
}

public struct IngestionSplitView: View {
    @ObservedObject var viewModel: IngestionViewModel
    @State private var selection: String? = nil

    public init(viewModel: IngestionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationSplitView {
            listView
        } detail: {
            detailView
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: selection) { _, newValue in
            guard let fileId = newValue else { return }
            Task { await viewModel.selectFile(fileId: fileId) }
        }
    }

    private var listView: some View {
        List {
            if viewModel.isLoading && viewModel.items.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading files...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.items.isEmpty {
                Text(viewModel.errorMessage ?? "No ingested files yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if !pinnedItems.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedItems, id: \.file.id) { item in
                            Button {
                                selection = item.file.id
                            } label: {
                                IngestionRow(item: item, isSelected: selection == item.file.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("All Files") {
                    ForEach(unpinnedItems, id: \.file.id) { item in
                        Button {
                            selection = item.file.id
                        } label: {
                            IngestionRow(item: item, isSelected: selection == item.file.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .refreshable {
            await viewModel.load()
        }
    }

    private var detailView: some View {
        Group {
            if let meta = viewModel.activeMeta {
                IngestionDetailView(viewModel: viewModel, meta: meta)
            } else {
                PlaceholderView(title: "Select a file")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinnedItems: [IngestionListItem] {
        viewModel.items
            .filter { $0.file.pinned ?? false }
            .sorted { ($0.file.pinnedOrder ?? 0) < ($1.file.pinnedOrder ?? 0) }
    }

    private var unpinnedItems: [IngestionListItem] {
        viewModel.items
            .filter { !($0.file.pinned ?? false) }
            .sorted { lhs, rhs in
                let left = DateParsing.parseISO8601(lhs.file.createdAt) ?? .distantPast
                let right = DateParsing.parseISO8601(rhs.file.createdAt) ?? .distantPast
                return left > right
            }
    }
}

private struct IngestionRow: View {
    let item: IngestionListItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(stripFileExtension(item.file.filenameOriginal))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let created = formattedDate {
                    Text(created)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.file.pinned == true {
                Image(systemName: "pin.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? selectionBackground : rowBackground)
    }

    private var iconName: String {
        switch item.recommendedViewer {
        case "viewer_pdf":
            return "doc.richtext"
        case "viewer_json":
            return "tablecells"
        case "viewer_video":
            return "video"
        case "image_original":
            return "photo"
        case "audio_original":
            return "waveform"
        case "text_original", "ai_md":
            return "doc.text"
        default:
            return "doc"
        }
    }

    private var statusText: String {
        if let message = item.job.userMessage, !message.isEmpty {
            return message
        }
        if let status = item.job.status {
            return status.capitalized
        }
        return "Processing"
    }

    private var formattedDate: String? {
        guard let date = DateParsing.parseISO8601(item.file.createdAt) else { return nil }
        return DateFormatter.ingestionRow.string(from: date)
    }

    private var selectionBackground: Color {
        #if os(macOS)
        return Color(nsColor: .selectedContentBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }

    private var rowBackground: Color {
        #if os(macOS)
        return Color(nsColor: .textBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }
}

private extension DateFormatter {
    static let ingestionRow: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
