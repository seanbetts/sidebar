import Foundation

@MainActor
@available(iOS 26.0, macOS 26.0, *)
enum AttributedNoteFormattingCommands {
    static func apply(_ formatting: NoteFormatting, on viewModel: NativeNoteEditorViewModel) {
        if applyInline(formatting, on: viewModel) {
            return
        }
        if applyBlock(formatting, on: viewModel) {
            return
        }
        applySpecial(formatting, on: viewModel)
    }

    private static func applyInline(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) -> Bool {
        switch formatting {
        case .bold:
            viewModel.toggleInlineIntent(.stronglyEmphasized)
            return true
        case .italic:
            viewModel.toggleInlineIntent(.emphasized)
            return true
        case .inlineCode:
            viewModel.toggleInlineIntent(.code)
            return true
        case .strikethrough:
            viewModel.toggleStrikethrough()
            return true
        default:
            return false
        }
    }

    private static func applyBlock(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) -> Bool {
        if applyHeadingCommands(formatting, on: viewModel) {
            return true
        }
        if applyListCommands(formatting, on: viewModel) {
            return true
        }
        if applyContainerCommands(formatting, on: viewModel) {
            return true
        }
        return false
    }

    private static func applyHeadingCommands(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) -> Bool {
        switch formatting {
        case .heading(let level):
            viewModel.setBlockKind(viewModel.headingKind(for: level))
            return true
        case .promoteHeading:
            viewModel.promoteHeading()
            return true
        case .demoteHeading:
            viewModel.demoteHeading()
            return true
        default:
            return false
        }
    }

    private static func applyListCommands(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) -> Bool {
        switch formatting {
        case .bulletList:
            viewModel.setBlockKind(.bulletList, listDepth: 1)
            return true
        case .orderedList:
            viewModel.setBlockKind(.orderedList, listDepth: 1)
            return true
        case .taskList:
            toggleTaskList(on: viewModel)
            return true
        case .indentList:
            viewModel.indentListItems()
            return true
        case .outdentList:
            viewModel.outdentListItems()
            return true
        default:
            return false
        }
    }

    private static func applyContainerCommands(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) -> Bool {
        switch formatting {
        case .blockquote:
            viewModel.setBlockKind(.blockquote)
            return true
        case .codeBlock:
            viewModel.applyCodeBlock(language: nil)
            return true
        default:
            return false
        }
    }

    private static func toggleTaskList(on viewModel: NativeNoteEditorViewModel) {
        let paragraphRanges = viewModel.selectedParagraphRanges()
        guard !paragraphRanges.isEmpty else {
            viewModel.setBlockKind(.taskUnchecked, listDepth: 1)
            return
        }

        for paragraphRange in paragraphRanges {
            let currentKind = viewModel.attributedContent[paragraphRange].blockKind
                ?? viewModel.attributedContent.blockKind(in: paragraphRange)
                ?? .paragraph
            let currentDepth = max(1, viewModel.attributedContent[paragraphRange].listDepth ?? 1)
            let nextKind: BlockKind
            switch currentKind {
            case .taskUnchecked:
                nextKind = .taskChecked
            case .taskChecked:
                nextKind = .taskUnchecked
            default:
                nextKind = .taskUnchecked
            }

            let nextDepth: Int? = viewModel.isListBlockKind(currentKind) ? currentDepth : 1
            viewModel.attributedContent[paragraphRange].blockKind = nextKind
            viewModel.attributedContent[paragraphRange].listDepth = nextDepth
            if nextKind != .codeBlock {
                viewModel.attributedContent[paragraphRange].codeLanguage = nil
            }
            viewModel.applyBlockStyle(blockKind: nextKind, range: paragraphRange)
            viewModel.applyPresentationIntent(
                blockKind: nextKind,
                listDepth: nextDepth,
                range: paragraphRange
            )
        }
    }

    private static func applySpecial(
        _ formatting: NoteFormatting,
        on viewModel: NativeNoteEditorViewModel
    ) {
        switch formatting {
        case .link(let url):
            viewModel.insertLink(url)
        case .horizontalRule:
            viewModel.insertHorizontalRule()
        default:
            return
        }
    }
}
