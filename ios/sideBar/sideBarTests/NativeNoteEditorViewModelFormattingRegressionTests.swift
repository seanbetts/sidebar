import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif
@testable import sideBar

@MainActor
@available(iOS 26.0, macOS 26.0, *)
final class NativeNoteEditorRegressionTests: XCTestCase {
    func testHandleContentChangePreservesUnderlineStyling() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("plain text")
        let lineRange = firstLine(in: viewModel.attributedContent)
        viewModel.attributedContent[lineRange].underlineStyle = .single

        let previous = viewModel.attributedContent
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)

        viewModel.handleContentChange(previous: previous)

        let updatedLine = firstLine(in: viewModel.attributedContent)
        XCTAssertEqual(viewModel.attributedContent[updatedLine].underlineStyle, .single)
    }

    func testLoadTextDetectsLinksUsingDataDetector() async {
        let viewModel = NativeNoteEditorViewModel()
        let urlString = "https://example.com"
        viewModel.loadText("Open \(urlString) for details")

        guard let linkRange = attributedRange(matching: urlString, in: viewModel.attributedContent) else {
            XCTFail("Expected detected link range")
            return
        }

        XCTAssertEqual(viewModel.attributedContent[linkRange].link, URL(string: urlString))
        XCTAssertEqual(viewModel.attributedContent[linkRange].underlineStyle, .single)
    }

    func testHandleContentChangeDetectsNewLinkText() async {
        let viewModel = NativeNoteEditorViewModel()
        let urlString = "https://example.com"
        viewModel.loadText("hello")
        let previous = viewModel.attributedContent

        viewModel.attributedContent = AttributedString("hello \(urlString)")
        let insertion = viewModel.attributedContent.endIndex
        viewModel.selection = AttributedTextSelection(range: insertion..<insertion)
        viewModel.handleContentChange(previous: previous)

        guard let linkRange = attributedRange(matching: urlString, in: viewModel.attributedContent) else {
            XCTFail("Expected detected link range")
            return
        }

        XCTAssertEqual(viewModel.attributedContent[linkRange].link, URL(string: urlString))
    }

    func testHandleContentChangeCanonicalizesSwiftUIFontOnlyBoldFormatting() async {
        let viewModel = NativeNoteEditorViewModel()
        viewModel.loadText("hello")
        let lineRange = firstLine(in: viewModel.attributedContent)
        let previous = viewModel.attributedContent

        viewModel.attributedContent[lineRange].font = .system(size: 16, weight: .bold)
        #if os(iOS)
        viewModel.attributedContent[lineRange][AttributeScopes.UIKitAttributes.FontAttribute.self] = nil
        #endif
        viewModel.handleContentChange(previous: previous)

        XCTAssertTrue((viewModel.attributedContent[lineRange].inlinePresentationIntent ?? []).contains(.stronglyEmphasized))
        XCTAssertTrue(viewModel.attributedContent.runs.contains { run in
            #if os(iOS)
            guard let font = run[AttributeScopes.UIKitAttributes.FontAttribute.self] else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.traitBold)
            #elseif os(macOS)
            guard let font = bridgedPlatformFont(from: run) as? NSFont else { return false }
            return font.fontDescriptor.symbolicTraits.contains(.bold)
            #endif
        })
    }

    private func firstLine(in text: AttributedString) -> Range<AttributedString.Index> {
        var cursor = text.startIndex
        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                return text.startIndex..<cursor
            }
            cursor = text.index(afterCharacter: cursor)
        }
        return text.startIndex..<text.endIndex
    }

    private func lineRanges(in text: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var start = text.startIndex
        var cursor = text.startIndex

        while cursor < text.endIndex {
            if text.characters[cursor].isNewline {
                ranges.append(start..<cursor)
                start = text.index(afterCharacter: cursor)
                cursor = start
            } else {
                cursor = text.index(afterCharacter: cursor)
            }
        }

        if start <= text.endIndex {
            ranges.append(start..<text.endIndex)
        }

        return ranges
    }

    private func attributedRange(
        matching substring: String,
        in text: AttributedString
    ) -> Range<AttributedString.Index>? {
        let plain = String(text.characters)
        guard let stringRange = plain.range(of: substring) else { return nil }
        let lowerOffset = plain.distance(from: plain.startIndex, to: stringRange.lowerBound)
        let upperOffset = plain.distance(from: plain.startIndex, to: stringRange.upperBound)
        let lower = text.index(text.startIndex, offsetByCharacters: lowerOffset)
        let upper = text.index(text.startIndex, offsetByCharacters: upperOffset)
        return lower..<upper
    }

#if os(macOS)
    private func bridgedPlatformFont(from run: AttributedString.Runs.Run) -> AnyObject? {
        var sample = AttributedString("x")
        let range = sample.startIndex..<sample.endIndex
        sample[range].mergeAttributes(run.attributes)
        let bridged = (try? NSAttributedString(sample, including: \.attributedNoteTextSurface))
            ?? NSAttributedString(sample)
        return bridged.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) as AnyObject?
    }
#endif
}
