import Foundation
import Combine

// TODO: Revisit to prefer native-first data sources where applicable.

@MainActor
public final class IngestionViewModel: ObservableObject {
    @Published public private(set) var items: [IngestionListItem] = []
    @Published public private(set) var activeMeta: IngestionMetaResponse? = nil
    @Published public private(set) var selectedFileId: String? = nil
    @Published public private(set) var selectedDerivativeKind: String? = nil
    @Published public private(set) var viewerState: FileViewerState? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingContent: Bool = false
    @Published public private(set) var isSelecting: Bool = false
    @Published public private(set) var isOffline: Bool = false
    @Published public private(set) var errorMessage: String? = nil

    private let api: any IngestionProviding
    private let temporaryStore: TemporaryFileStore
    private let store: IngestionStore
    private var cancellables = Set<AnyCancellable>()

    public init(
        api: any IngestionProviding,
        store: IngestionStore,
        temporaryStore: TemporaryFileStore
    ) {
        self.api = api
        self.temporaryStore = temporaryStore
        self.store = store

        store.$items
            .sink { [weak self] items in
                self?.items = items
            }
            .store(in: &cancellables)

        store.$activeMeta
            .sink { [weak self] meta in
                self?.activeMeta = meta
            }
            .store(in: &cancellables)

        store.$isOffline
            .sink { [weak self] isOffline in
                self?.isOffline = isOffline
            }
            .store(in: &cancellables)
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        do {
            try await store.loadList()
        } catch {
            if items.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadMeta(fileId: String) async {
        errorMessage = nil
        do {
            try await store.loadMeta(fileId: fileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectFile(fileId: String) async {
        isSelecting = true
        defer { isSelecting = false }
        prepareSelection(fileId: fileId)
        await loadMeta(fileId: fileId)
        guard let meta = activeMeta else { return }
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
    }

    public func prepareSelection(fileId: String) {
        selectedFileId = fileId
        viewerState = nil
        selectedDerivativeKind = nil
    }

    public func selectDerivative(kind: String) async {
        selectedDerivativeKind = kind
        guard let meta = activeMeta else { return }
        guard let derivative = meta.derivatives.first(where: { $0.kind == kind }) else { return }
        await loadDerivativeContent(meta: meta, derivative: derivative)
    }

    public func togglePinned(fileId: String, pinned: Bool) async {
        errorMessage = nil
        do {
            try await api.pin(fileId: fileId, pinned: pinned)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func applyIngestedFileEvent(_ payload: RealtimePayload<IngestedFileRealtimeRecord>) async {
        store.applyIngestedFileEvent(payload)
        if let selectedFileId, selectedFileId == payload.record?.id || selectedFileId == payload.oldRecord?.id {
            await loadMeta(fileId: selectedFileId)
        }
    }

    public func applyFileJobEvent(_ payload: RealtimePayload<FileJobRealtimeRecord>) async {
        store.applyFileJobEvent(payload)
        if let selectedFileId, selectedFileId == payload.record?.fileId {
            await loadMeta(fileId: selectedFileId)
        }
    }

    public func clearSelection() {
        selectedFileId = nil
        store.clearActiveMeta()
        selectedDerivativeKind = nil
        viewerState = nil
        errorMessage = nil
    }

    private func preferredDerivativeKind(for meta: IngestionMetaResponse) -> String? {
        let candidates = meta.derivatives.filter { $0.kind != "thumb_png" }
        let nonAI = candidates.filter { $0.kind != "ai_md" }

        if let recommended = meta.recommendedViewer {
            if recommended == "ai_md" {
                return nonAI.first?.kind ?? "ai_md"
            }
            if recommended == "viewer_video",
               meta.derivatives.contains(where: { $0.kind == "video_original" }) {
                return "video_original"
            }
            if meta.derivatives.contains(where: { $0.kind == recommended }) {
                return recommended
            }
        }
        return nonAI.first?.kind ?? candidates.first?.kind
    }

    private func loadDerivativeContent(meta: IngestionMetaResponse, derivative: IngestionDerivative) async {
        isLoadingContent = true
        errorMessage = nil
        do {
            let data = try await api.getContent(fileId: meta.file.id, kind: derivative.kind, range: nil)
            let inferredKind = FileViewerKind.infer(path: nil, mimeType: derivative.mime, derivativeKind: derivative.kind)
            let kind = overrideKindIfMarkdown(
                inferredKind: inferredKind,
                filename: meta.file.filenameOriginal,
                mimeType: derivative.mime
            )
            let filename = makeFilename(base: meta.file.filenameOriginal, mimeType: derivative.mime, fallback: derivative.kind)
            let youtubeEmbedURL = buildYouTubeEmbedURL(from: meta.file)
            switch kind {
            case .markdown, .text, .json:
                let rawText = String(decoding: data, as: UTF8.self)
                let shouldStrip = derivative.kind == "ai_md" || kind == .markdown
                let text = shouldStrip ? MarkdownRendering.stripFrontmatter(rawText) : rawText
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: text,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            case .spreadsheet:
                let spreadsheet = try? JSONDecoder().decode(SpreadsheetPayload.self, from: data)
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: .spreadsheet,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: spreadsheet,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            default:
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: nil,
                    youtubeEmbedURL: youtubeEmbedURL
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingContent = false
    }

    private func makeFilename(base: String, mimeType: String, fallback: String) -> String {
        if base.contains(".") {
            return base
        }
        if let ext = filenameExtension(for: mimeType) {
            return "\(base).\(ext)"
        }
        return "\(base)-\(fallback)"
    }

    private func filenameExtension(for mimeType: String) -> String? {
        let normalized = mimeType.lowercased()
        switch normalized {
        case "application/pdf":
            return "pdf"
        case "application/json":
            return "json"
        case "text/markdown":
            return "md"
        case "text/plain":
            return "txt"
        case "text/csv":
            return "csv"
        case "text/tab-separated-values":
            return "tsv"
        default:
            if normalized.hasPrefix("image/") {
                return normalized.replacingOccurrences(of: "image/", with: "")
            }
            if normalized.hasPrefix("audio/") {
                return normalized.replacingOccurrences(of: "audio/", with: "")
            }
            if normalized.hasPrefix("video/") {
                return normalized.replacingOccurrences(of: "video/", with: "")
            }
            return nil
        }
    }

    private func overrideKindIfMarkdown(
        inferredKind: FileViewerKind,
        filename: String,
        mimeType: String
    ) -> FileViewerKind {
        if inferredKind == .text {
            let lower = filename.lowercased()
            if lower.hasSuffix(".md") || lower.hasSuffix(".markdown") {
                return .markdown
            }
            if mimeType.lowercased() == "text/markdown" {
                return .markdown
            }
        }
        return inferredKind
    }

    private func buildYouTubeEmbedURL(from file: IngestedFileMeta) -> URL? {
        if let metadata = file.sourceMetadata {
            if let value = metadata["video_id"]?.value as? String {
                return makeYouTubeEmbedURL(videoId: value)
            }
            if let value = metadata["youtube_url"]?.value as? String,
               let videoId = extractYouTubeVideoId(from: value) {
                return makeYouTubeEmbedURL(videoId: videoId)
            }
        }
        if let raw = file.sourceUrl,
           let videoId = extractYouTubeVideoId(from: raw) {
            return makeYouTubeEmbedURL(videoId: videoId)
        }
        return nil
    }

    private func makeYouTubeEmbedURL(videoId: String) -> URL? {
        let trimmed = videoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = "https://www.youtube-nocookie.com/embed/\(trimmed)?playsinline=1&rel=0&modestbranding=1"
        return URL(string: url)
    }

    private func extractYouTubeVideoId(from raw: String) -> String? {
        guard let components = URLComponents(string: raw) else { return nil }
        if let host = components.host {
            if host.contains("youtu.be") {
                let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                return path.isEmpty ? nil : path
            }
            if host.contains("youtube.com") || host.contains("youtube-nocookie.com") {
                if components.path.hasPrefix("/watch") {
                    if let queryItem = components.queryItems?.first(where: { $0.name == "v" }) {
                        return queryItem.value
                    }
                }
                if components.path.hasPrefix("/embed/") {
                    let path = components.path.replacingOccurrences(of: "/embed/", with: "")
                    return path.isEmpty ? nil : path
                }
                if components.path.hasPrefix("/shorts/") {
                    let path = components.path.replacingOccurrences(of: "/shorts/", with: "")
                    return path.isEmpty ? nil : path
                }
            }
        }
        if raw.contains("youtu.be/") {
            if let range = raw.range(of: "youtu.be/") {
                let tail = raw[range.upperBound...]
                let id = tail.split(separator: "?").first.map(String.init)
                return id?.isEmpty == true ? nil : id
            }
        }
        return nil
    }
}
