import Foundation
import OSLog

struct NotesUnsupportedContent: Equatable {
    static let placeholderTitle = "Unsupported note content"

    let blockTypes: [NotesSemanticDocument.BlockType]

    var placeholderMessage: String {
        let labels = blockTypes.map(\.displayName).joined(separator: ", ")
        return "This note contains unsupported content blocks: \(labels)."
    }

    static func detect(in document: NotesSemanticDocument) -> NotesUnsupportedContent? {
        var blockTypes: [NotesSemanticDocument.BlockType] = []
        for block in document.blocks where !supportedBlockTypes.contains(block.type) {
            if !blockTypes.contains(block.type) {
                blockTypes.append(block.type)
            }
        }
        guard !blockTypes.isEmpty else { return nil }
        return NotesUnsupportedContent(blockTypes: blockTypes)
    }

    func reportDetected(
        context: String,
        logger: Logger = Logger(subsystem: "sideBar", category: "NotesUnsupportedContent")
    ) {
        let labels = blockTypes.map(\.rawValue).joined(separator: ",")
        logger.error(
            "Unsupported notes content detected in \(context, privacy: .public): \(labels, privacy: .public)"
        )
        guard !ProcessInfo.processInfo.isRunningTests else { return }
        assertionFailure("Unsupported notes content detected in \(context): \(labels)")
    }
}

private extension NotesUnsupportedContent {
    static let supportedBlockTypes: Set<NotesSemanticDocument.BlockType> = [
        .title,
        .paragraph,
        .heading,
        .subheading,
        .unorderedList,
        .orderedList,
        .checklist,
        .listItem,
        .blockquote,
        .codeBlock
    ]
}

private extension NotesSemanticDocument.BlockType {
    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
    }
}

private extension ProcessInfo {
    var isRunningTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
