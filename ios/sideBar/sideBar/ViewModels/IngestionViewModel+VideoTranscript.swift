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
            let transcript = sanitizeVideoTranscript(rawText)
            guard !transcript.isEmpty else { return nil }
            return isHeadingOnly(transcript) ? nil : transcript
        } catch {
            return nil
        }
    }

    private func sanitizeVideoTranscript(_ content: String) -> String {
        var transcript = MarkdownRendering.stripFrontmatter(content)
        transcript = MarkdownRendering.stripWebsiteTranscriptArtifacts(transcript)
        transcript = stripLegacyTranscriptMetadata(transcript)
        transcript = stripLeadingMetadataSection(transcript)
        transcript = stripLeadingMetadataLines(transcript)
        transcript = demoteLeadingH1(transcript)
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripLegacyTranscriptMetadata(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let separatorIndex = lines.firstIndex(where: { isSeparatorLine($0) }),
              separatorIndex > 0 else {
            return normalized
        }
        let metadataLines = lines[..<separatorIndex]
        guard metadataLines.contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }) else {
            return normalized
        }
        return lines[(separatorIndex + 1)...].joined(separator: "\n")
    }

    private func stripLeadingMetadataSection(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        var index = firstContentLineIndex(in: lines)

        // Preserve a leading document title, then inspect the next heading.
        if index < lines.count && isH1Line(lines[index]) {
            index += 1
            while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }
        }
        guard index < lines.count else { return lines.joined(separator: "\n") }
        guard isMetadataHeading(lines[index]) else { return lines.joined(separator: "\n") }

        var end = index + 1
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#"), !isMetadataHeading(trimmed) {
                break
            }
            end += 1
        }
        lines.removeSubrange(index..<end)
        return lines.joined(separator: "\n")
    }

    private func stripLeadingMetadataLines(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        var index = firstContentLineIndex(in: lines)

        // Preserve a leading document title, then inspect the next block.
        if index < lines.count && isH1Line(lines[index]) {
            index += 1
            while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }
        }

        var end = index
        var sawMetadataLine = false
        while end < lines.count {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if sawMetadataLine {
                    end += 1
                    continue
                }
                break
            }
            if isMetadataLine(trimmed) {
                sawMetadataLine = true
                end += 1
                continue
            }
            break
        }
        guard sawMetadataLine else { return lines.joined(separator: "\n") }
        lines.removeSubrange(index..<end)
        return lines.joined(separator: "\n")
    }

    private func demoteLeadingH1(_ text: String) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let index = firstContentLineIndex(in: lines)
        guard index < lines.count, isH1Line(lines[index]) else {
            return lines.joined(separator: "\n")
        }
        let title = lines[index].dropFirst(2)
        lines[index] = "## \(title)"
        return lines.joined(separator: "\n")
    }

    private func firstContentLineIndex(in lines: [String]) -> Int {
        var index = 0
        while index < lines.count && lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        return index
    }

    private func isH1Line(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("# ") && !trimmed.hasPrefix("## ")
    }

    private func isMetadataHeading(_ line: String) -> Bool {
        let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lowercased == "# metadata"
            || lowercased == "## metadata"
            || lowercased == "### metadata"
    }

    private func isSeparatorLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    private func isMetadataLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        let candidate = normalizeMetadataCandidate(normalized)
        let prefixes = [
            "youtube url:",
            "source:",
            "video title:",
            "title:",
            "type:",
            "filename:",
            "generated:",
            "model:",
            "file size:",
            "usage:",
            "audio tokens:",
            "original file:",
            "duration:",
            "download duration:",
            "download duration (seconds):",
            "download time:",
            "transcription time:"
        ]
        if prefixes.contains(where: { candidate.hasPrefix($0) }) {
            return true
        }
        return isStatusLine(candidate)
    }

    private func normalizeMetadataCandidate(_ line: String) -> String {
        var value = line
        if value.hasPrefix("# ") {
            value = String(value.dropFirst(2))
        }
        if value.hasPrefix("- ") || value.hasPrefix("* ") {
            value = String(value.dropFirst(2))
        }
        if value.hasPrefix("**"), let end = value.firstIndex(of: ":") {
            value = String(value[..<end]) + ":" + String(value[value.index(after: end)...])
            value = value.replacingOccurrences(of: "**", with: "")
        } else {
            value = value.replacingOccurrences(of: "**", with: "")
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private func isStatusLine(_ line: String) -> Bool {
        let normalized = line
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statuses = Set([
            "download completed successfully.",
            "download completed successfully",
            "transcription completed successfully.",
            "transcription completed successfully",
            "================================================================================"
        ])
        return statuses.contains(normalized)
    }

    private func isHeadingOnly(_ text: String) -> Bool {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, let first = lines.first else { return false }
        return first.hasPrefix("#")
    }
}
