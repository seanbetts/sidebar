import Foundation

// MARK: - IngestionViewModel+VideoTranscript

extension IngestionViewModel {
    func transcriptForVideoIfAvailable(
        meta: IngestionMetaResponse,
        kind: FileViewerKind
    ) async -> String? {
        guard kind == .video else { return nil }
        guard meta.derivatives.contains(where: { $0.kind == "ai_md" }) else {
            return nil
        }
        do {
            let data = try await api.getContent(
                fileId: meta.file.id,
                kind: "ai_md",
                range: nil
            )
            let rawText = String(bytes: data, encoding: .utf8) ?? ""
            let transcript = MarkdownRendering
                .stripFrontmatter(rawText)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return transcript.isEmpty ? nil : transcript
        } catch {
            return nil
        }
    }
}
