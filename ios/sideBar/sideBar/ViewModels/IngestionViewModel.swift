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
    @Published public private(set) var errorMessage: String? = nil

    private let api: any IngestionProviding
    private let cache: CacheClient
    private let temporaryStore: TemporaryFileStore

    public init(
        api: any IngestionProviding,
        cache: CacheClient,
        temporaryStore: TemporaryFileStore
    ) {
        self.api = api
        self.cache = cache
        self.temporaryStore = temporaryStore
    }

    public func load() async {
        isLoading = true
        errorMessage = nil
        let cached: IngestionListResponse? = cache.get(key: CacheKeys.ingestionList)
        if let cached {
            items = cached.items
        }
        do {
            let response = try await api.list()
            items = response.items
            cache.set(key: CacheKeys.ingestionList, value: response, ttlSeconds: CachePolicy.ingestionList)
        } catch {
            if cached == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    public func loadMeta(fileId: String) async {
        errorMessage = nil
        do {
            activeMeta = try await api.getMeta(fileId: fileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func selectFile(fileId: String) async {
        selectedFileId = fileId
        viewerState = nil
        selectedDerivativeKind = nil
        await loadMeta(fileId: fileId)
        guard let meta = activeMeta else { return }
        if let kind = preferredDerivativeKind(for: meta) {
            await selectDerivative(kind: kind)
        }
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

    public func applyRealtimeEvent() async {
        await load()
        if let selectedFileId {
            await loadMeta(fileId: selectedFileId)
        }
    }

    private func preferredDerivativeKind(for meta: IngestionMetaResponse) -> String? {
        if let recommended = meta.recommendedViewer {
            if recommended == "viewer_video",
               meta.derivatives.contains(where: { $0.kind == "video_original" }) {
                return "video_original"
            }
            if meta.derivatives.contains(where: { $0.kind == recommended }) {
                return recommended
            }
        }
        return meta.derivatives.first(where: { $0.kind != "thumb_png" })?.kind
    }

    private func loadDerivativeContent(meta: IngestionMetaResponse, derivative: IngestionDerivative) async {
        isLoadingContent = true
        errorMessage = nil
        do {
            let data = try await api.getContent(fileId: meta.file.id, kind: derivative.kind, range: nil)
            let kind = FileViewerKind.infer(path: nil, mimeType: derivative.mime, derivativeKind: derivative.kind)
            let filename = makeFilename(base: meta.file.filenameOriginal, mimeType: derivative.mime, fallback: derivative.kind)
            switch kind {
            case .markdown, .text, .json:
                let text = String(decoding: data, as: UTF8.self)
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: text,
                    fileURL: fileURL,
                    spreadsheet: nil
                )
            case .spreadsheet:
                let spreadsheet = try? JSONDecoder().decode(SpreadsheetPayload.self, from: data)
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: .spreadsheet,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: spreadsheet
                )
            default:
                let fileURL = try temporaryStore.store(data: data, filename: filename)
                viewerState = FileViewerState(
                    title: meta.file.filenameOriginal,
                    kind: kind,
                    text: nil,
                    fileURL: fileURL,
                    spreadsheet: nil
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
}
