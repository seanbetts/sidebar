@preconcurrency import Foundation
import SwiftUI

@MainActor
@available(iOS 26.0, macOS 26.0, *)
extension NativeNoteEditorViewModel {
    private static let linkDetector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    @discardableResult
    func applyDetectedLinks(in text: inout AttributedString) -> Bool {
        guard let detector = Self.linkDetector else { return false }
        let plainText = String(text.characters)
        guard !plainText.isEmpty else { return false }
        let nsRange = NSRange(location: 0, length: (plainText as NSString).length)
        let matches = detector.matches(in: plainText, options: [], range: nsRange)
        guard !matches.isEmpty else { return false }

        var didChange = false
        for match in matches {
            guard let url = match.url else { continue }
            guard let stringRange = Range(match.range, in: plainText) else { continue }
            guard let attributedRange = attributedRange(for: stringRange, in: plainText, text: text) else {
                continue
            }
            guard !attributedRange.isEmpty else { continue }
            guard !text[attributedRange].runs.contains(where: { $0.link != nil }) else { continue }

            text[attributedRange].link = url
            if text[attributedRange].underlineStyle == nil {
                text[attributedRange].underlineStyle = .single
            }
            didChange = true
        }

        return didChange
    }

    private func attributedRange(
        for stringRange: Range<String.Index>,
        in text: String,
        text attributedText: AttributedString
    ) -> Range<AttributedString.Index>? {
        let lowerOffset = text.distance(from: text.startIndex, to: stringRange.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: stringRange.upperBound)
        guard lowerOffset <= upperOffset else { return nil }
        let lowerIndex = attributedText.index(attributedText.startIndex, offsetByCharacters: lowerOffset)
        let upperIndex = attributedText.index(attributedText.startIndex, offsetByCharacters: upperOffset)
        return lowerIndex..<upperIndex
    }
}
