@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    struct TableRowInfo {
        let isHeader: Bool
        let rowIndex: Int?
        let alignments: [PresentationIntent.TableColumn.Alignment]?
    }

    func unionLineSpan(
        _ lhs: ClosedRange<Int>?,
        _ rhs: ClosedRange<Int>?
    ) -> ClosedRange<Int>? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return min(lhs.lowerBound, rhs.lowerBound)...max(lhs.upperBound, rhs.upperBound)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    func requiresStructuralPrefixRefresh(
        previous: AttributedString,
        current: AttributedString,
        insertedCharacter: Character?,
        didApplyShortcutMutation: Bool
    ) -> Bool {
        if didApplyShortcutMutation {
            return true
        }
        if insertedCharacter?.isNewline == true {
            return true
        }
        let previousText = String(previous.characters)
        let currentText = String(current.characters)
        if previousText.count != currentText.count, insertedCharacter == nil {
            // Treat deletions/replacements/pastes as structural edits.
            return true
        }
        let previousLineCount = previousText.reduce(into: 1) { count, character in
            if character.isNewline {
                count += 1
            }
        }
        let currentLineCount = currentText.reduce(into: 1) { count, character in
            if character.isNewline {
                count += 1
            }
        }
        return previousLineCount != currentLineCount
    }

    func tableRowInfo(from intent: PresentationIntent?) -> TableRowInfo? {
        guard let intent else { return nil }
        var isHeader = false
        var rowIndex: Int?
        var foundRow = false

        for component in intent.components {
            switch component.kind {
            case .tableHeaderRow:
                isHeader = true
                rowIndex = 0
                foundRow = true
            case .tableRow(let index):
                rowIndex = index
                foundRow = true
            default:
                break
            }
        }

        guard foundRow else { return nil }
        return TableRowInfo(isHeader: isHeader, rowIndex: rowIndex, alignments: nil)
    }

    func tableRowBackground(from info: TableRowInfo?) -> Color? {
        guard let info else { return nil }
        if info.isHeader {
            return DesignTokens.Colors.muted
        }
        if let rowIndex = info.rowIndex, rowIndex % 2 == 1 {
            return DesignTokens.Colors.muted.opacity(0.4)
        }
        return nil
    }
}
