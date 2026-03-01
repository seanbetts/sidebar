import Foundation
import sideBarShared

enum PromptPreviewWorkspaceSurfaceFactory {
    static let surfaceId = "prompt-preview"

    static func makeSurface(
        from preview: ChatPromptPreview
    ) -> AgentWorkspaceSurfaceDescriptor? {
        let markdown = promptPreviewWorkspaceMarkdown(preview)
        guard !markdown.isEmpty else { return nil }

        return AgentWorkspaceSurfaceDescriptor(
            type: .markdown,
            surfaceId: surfaceId,
            title: "System Prompt",
            payload: [
                "markdown": markdown,
                "summary": "Generated from current system and first-message prompts."
            ],
            capabilities: AgentWorkspaceSurfaceCapabilities(
                canRefresh: false,
                canClose: true,
                canPin: true,
                canInspectData: true
            )
        )
    }

    private static func promptPreviewWorkspaceMarkdown(_ preview: ChatPromptPreview) -> String {
        var blocks: [String] = []

        if let report = preview.promptReport {
            var reportLines: [String] = ["## Prompt Report"]
            if let system = report.systemPrompt {
                reportLines.append("- System: \(promptReportSummary(system))")
            }
            if let first = report.firstMessagePrompt {
                reportLines.append("- First message: \(promptReportSummary(first))")
            }
            if reportLines.count > 1 {
                blocks.append(reportLines.joined(separator: "\n"))
            }
        }

        if !preview.systemPromptSections.isEmpty {
            blocks.append(
                sectionSummaryBlock(
                    title: "System Sections",
                    sections: preview.systemPromptSections
                )
            )
        }

        if !preview.firstMessagePromptSections.isEmpty {
            blocks.append(
                sectionSummaryBlock(
                    title: "First-Message Sections",
                    sections: preview.firstMessagePromptSections
                )
            )
        }

        if let systemPrompt = preview.systemPrompt?.trimmedOrNil {
            blocks.append("## System Prompt\n\n\(formattedPromptDocument(systemPrompt))")
        }

        if let firstPrompt = preview.firstMessagePrompt?.trimmedOrNil {
            blocks.append("## First Message Prompt\n\n\(formattedPromptDocument(firstPrompt))")
        }

        return blocks.joined(separator: "\n\n---\n\n")
    }

    private static func promptReportSummary(_ document: ChatPromptReportDocument) -> String {
        let base = "\(document.totalChars)/\(document.maxChars) chars"
        return document.truncated ? "\(base) (truncated)" : base
    }

    private static func sectionSummaryBlock(
        title: String,
        sections: [ChatPromptSection]
    ) -> String {
        let lines = sections.map { section in
            "- \(section.id) (\(section.chars)) · \(section.source)"
        }
        return (["## \(title)"] + lines).joined(separator: "\n")
    }

    private static func formattedPromptDocument(_ prompt: String) -> String {
        let lines = prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isWrapperTagLine(trimmed) {
                if output.last?.isEmpty == false {
                    output.append("")
                }
                output.append("`\(trimmed)`")
                output.append("")
                continue
            }
            output.append(line)
        }

        return collapseExtraBlankLines(output.joined(separator: "\n"))
    }

    private static func isWrapperTagLine(_ line: String) -> Bool {
        let pattern = #"^</?[A-Za-z][A-Za-z0-9_-]*>$"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func collapseExtraBlankLines(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
    }
}
