import Foundation

@MainActor
@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteListCommands {
    private enum Direction {
        case indent
        case outdent
    }

    private static let maxDepth = 8

    static func indent(on viewModel: NativeNoteEditorViewModel) {
        adjustDepth(on: viewModel, direction: .indent)
    }

    static func outdent(on viewModel: NativeNoteEditorViewModel) {
        adjustDepth(on: viewModel, direction: .outdent)
    }

    private static func adjustDepth(
        on viewModel: NativeNoteEditorViewModel,
        direction: Direction
    ) {
        let paragraphRanges = viewModel.selectedParagraphRanges()
        for paragraphRange in paragraphRanges {
            let blockKind = viewModel.attributedContent.blockKind(in: paragraphRange) ?? .paragraph
            guard viewModel.isListBlockKind(blockKind) else { continue }

            let currentDepth = max(1, viewModel.attributedContent[paragraphRange].listDepth ?? 1)
            let target = targetState(blockKind: blockKind, currentDepth: currentDepth, direction: direction)

            viewModel.attributedContent[paragraphRange].blockKind = target.blockKind
            viewModel.attributedContent[paragraphRange].listDepth = target.depth
            viewModel.applyBlockStyle(blockKind: target.blockKind, range: paragraphRange)
            viewModel.applyPresentationIntent(
                blockKind: target.blockKind,
                listDepth: target.depth,
                range: paragraphRange
            )
        }
    }

    private static func targetState(
        blockKind: BlockKind,
        currentDepth: Int,
        direction: Direction
    ) -> (blockKind: BlockKind, depth: Int?) {
        switch direction {
        case .indent:
            let depth = min(maxDepth, currentDepth + 1)
            return (blockKind, depth)
        case .outdent:
            if currentDepth > 1 {
                return (blockKind, currentDepth - 1)
            }
            return (.paragraph, nil)
        }
    }
}
