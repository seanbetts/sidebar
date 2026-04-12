import Foundation

private extension FileViewerKind {
    var supportsCopyText: Bool {
        switch self {
        case .markdown, .text, .json:
            return true
        default:
            return false
        }
    }
}

extension IngestionViewModel {
    var canCopyTextForSelectedFile: Bool {
        guard let selectedFileId else { return false }
        if let meta = activeMeta, meta.file.id == selectedFileId {
            return canCopyText(for: meta)
        }
        guard let item = items.first(where: { $0.file.id == selectedFileId }) else {
            return false
        }
        return canCopyText(for: item)
    }

    func canCopyText(for item: IngestionListItem) -> Bool {
        if let meta = cachedMetaForCopyText(fileId: item.file.id) {
            return canCopyText(for: meta)
        }
        guard !isCopyTextExcludedMedia(
            mimeType: item.file.mimeOriginal,
            recommendedViewer: item.recommendedViewer
        ) else {
            return false
        }
        let inferredKind = FileViewerKind.infer(
            path: item.file.path,
            mimeType: item.file.mimeOriginal,
            derivativeKind: item.recommendedViewer
        )
        return inferredKind.supportsCopyText || inferredKind == .pdf
    }

    func loadCopyTextContent(fileId: String) async -> String? {
        if let cached = cachedViewerTextForCopy(fileId: fileId) {
            return cached
        }
        guard let meta = try? await metaForCopyText(fileId: fileId) else {
            return nil
        }
        guard let derivative = preferredCopyTextDerivative(for: meta) else {
            return nil
        }
        do {
            let data = try await api.getContent(fileId: fileId, kind: derivative.kind, range: nil)
            return decodeCopyText(data: data, derivative: derivative, meta: meta)
        } catch {
            return nil
        }
    }

    private func canCopyText(for meta: IngestionMetaResponse) -> Bool {
        preferredCopyTextDerivative(for: meta) != nil
    }

    private func cachedMetaForCopyText(fileId: String) -> IngestionMetaResponse? {
        if let activeMeta, activeMeta.file.id == fileId {
            return activeMeta
        }
        let cacheKey = CacheKeys.ingestionMeta(fileId: fileId)
        if let cached: IngestionMetaResponse = store.cache.get(key: cacheKey) {
            return cached
        }
        return store.offlineStore?.get(key: cacheKey, as: IngestionMetaResponse.self)
    }

    private func cachedViewerTextForCopy(fileId: String) -> String? {
        guard let activeMeta, activeMeta.file.id == fileId else { return nil }
        guard let viewerState, viewerState.kind.supportsCopyText else { return nil }
        return trimmedCopyText(viewerState.text)
    }

    private func metaForCopyText(fileId: String) async throws -> IngestionMetaResponse {
        if let cached = cachedMetaForCopyText(fileId: fileId) {
            return cached
        }
        return try await api.getMeta(fileId: fileId)
    }

    private func preferredCopyTextDerivative(for meta: IngestionMetaResponse) -> IngestionDerivative? {
        guard !isCopyTextExcludedMedia(
            mimeType: meta.file.mimeOriginal,
            recommendedViewer: meta.recommendedViewer
        ) else {
            return nil
        }

        let preferredKinds = ["text_original", "source_original", "ai_md"]
        for kind in preferredKinds {
            if let derivative = meta.derivatives.first(where: { $0.kind == kind }),
               derivativeSupportsCopyText(derivative, meta: meta) {
                return derivative
            }
        }

        return meta.derivatives.first(where: { derivativeSupportsCopyText($0, meta: meta) })
    }

    private func derivativeSupportsCopyText(
        _ derivative: IngestionDerivative,
        meta: IngestionMetaResponse
    ) -> Bool {
        let inferredKind = FileViewerKind.infer(
            path: meta.file.path,
            mimeType: derivative.mime,
            derivativeKind: derivative.kind
        )
        let kind = overrideKindIfMarkdown(
            inferredKind: inferredKind,
            filename: meta.file.filenameOriginal,
            mimeType: derivative.mime
        )
        return kind.supportsCopyText
    }

    private func decodeCopyText(
        data: Data,
        derivative: IngestionDerivative,
        meta: IngestionMetaResponse
    ) -> String? {
        let rawText = String(bytes: data, encoding: .utf8) ?? ""
        let inferredKind = FileViewerKind.infer(
            path: meta.file.path,
            mimeType: derivative.mime,
            derivativeKind: derivative.kind
        )
        let kind = overrideKindIfMarkdown(
            inferredKind: inferredKind,
            filename: meta.file.filenameOriginal,
            mimeType: derivative.mime
        )
        guard kind.supportsCopyText else { return nil }
        let shouldStripFrontmatter = derivative.kind == "ai_md" || kind == .markdown
        let text = shouldStripFrontmatter ? MarkdownRendering.stripFrontmatter(rawText) : rawText
        return trimmedCopyText(text)
    }

    private func trimmedCopyText(_ text: String?) -> String? {
        guard let text else { return nil }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    private func isCopyTextExcludedMedia(
        mimeType: String?,
        recommendedViewer: String?
    ) -> Bool {
        if recommendedViewer == "viewer_video" || recommendedViewer == "video_original" {
            return true
        }
        let normalizedMime = mimeType?
            .split(separator: ";")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedMime else { return false }
        return normalizedMime.hasPrefix("image/")
            || normalizedMime.hasPrefix("audio/")
            || normalizedMime.hasPrefix("video/")
    }
}
