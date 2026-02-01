import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum CodeBlockAttachmentBuilder {
    static func displayText(
        from text: AttributedString,
        renderCodeBlocks: Bool = true,
        renderHorizontalRules: Bool = true
    ) -> NSAttributedString {
        let source = applyStrikethroughAttributes(from: text, to: NSAttributedString(text))
        return buildDisplayText(
            from: source,
            renderCodeBlocks: renderCodeBlocks,
            renderHorizontalRules: renderHorizontalRules
        )
    }

    static func applyStrikethroughAttributes(
        from text: AttributedString,
        to source: NSAttributedString
    ) -> NSAttributedString {
        guard !text.characters.isEmpty else { return source }
        let mutable = NSMutableAttributedString(attributedString: source)
        let string = source.string
        for run in text.runs {
            guard run.strikethroughStyle != nil else { continue }
            let startOffset = text.characters.distance(from: text.startIndex, to: run.range.lowerBound)
            let endOffset = text.characters.distance(from: text.startIndex, to: run.range.upperBound)
            guard startOffset < endOffset else { continue }
            let startIndex = string.index(string.startIndex, offsetBy: startOffset)
            let endIndex = string.index(string.startIndex, offsetBy: endOffset)
            let range = NSRange(startIndex..<endIndex, in: string)
            mutable.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        return mutable
    }

    private static func buildDisplayText(
        from source: NSAttributedString,
        renderCodeBlocks: Bool,
        renderHorizontalRules: Bool
    ) -> NSAttributedString {
        let string = source.string as NSString
        let lineRanges = lineRanges(in: string)
        let result = NSMutableAttributedString()
        var index = 0

        while index < lineRanges.count {
            let lineRange = lineRanges[index]
            let kind = blockKind(in: lineRange, in: source)
            if renderCodeBlocks, kind == .codeBlock {
                var codeLines: [String] = []
                let startIndex = index
                var endIndex = index
                while endIndex < lineRanges.count {
                    guard shouldIncludeInCodeBlock(
                        at: endIndex,
                        lineRanges: lineRanges,
                        source: source
                    ) else { break }
                    let range = lineRanges[endIndex]
                    codeLines.append(string.substring(with: range))
                    endIndex += 1
                }

                let firstAttrIndex = firstAttributedLineIndex(
                    in: startIndex..<endIndex,
                    lineRanges: lineRanges,
                    source: source
                ) ?? startIndex
                let lastAttrIndex = lastAttributedLineIndex(
                    in: startIndex..<endIndex,
                    lineRanges: lineRanges,
                    source: source
                ) ?? max(startIndex, endIndex - 1)
                let firstAttrs = safeAttributes(at: lineRanges[firstAttrIndex].location, in: source)
                let lastAttrs = safeAttributes(at: lineRanges[lastAttrIndex].location, in: source)
                let attachment = makeAttachment(code: codeLines.joined(separator: "\n"), firstAttrs: firstAttrs, lastAttrs: lastAttrs)
                result.append(attachment)

                if endIndex < lineRanges.count {
                    let newlineAttrs = safeAttributes(at: min(lineRanges[endIndex].location, max(0, source.length - 1)), in: source)
                    result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                }

                index = endIndex
                continue
            }

            if renderHorizontalRules,
               kind != .codeBlock,
               isThematicBreakLine(lineRange, blockKind: kind, string: string) {
                let attrs = safeAttributes(at: lineRange.location, in: source)
                let paragraphStyle = (attrs[.paragraphStyle] as? NSParagraphStyle) ?? NSMutableParagraphStyle()
                let attachment = makeHorizontalRuleAttachment(
                    paragraphStyle: paragraphStyle,
                    attrs: attrs
                )
                result.append(attachment)
                if index < lineRanges.count - 1 {
                    let newlineAttrs = safeAttributes(at: min(lineRange.location, max(0, source.length - 1)), in: source)
                    result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
                }
                index += 1
                continue
            }

            if lineRange.length > 0 {
                result.append(source.attributedSubstring(from: lineRange))
            }
            if index < lineRanges.count - 1 {
                let newlineAttrs = safeAttributes(at: min(lineRange.location, max(0, source.length - 1)), in: source)
                result.append(NSAttributedString(string: "\n", attributes: newlineAttrs))
            }
            index += 1
        }

        return result
    }

    private static func makeAttachment(
        code: String,
        firstAttrs: [NSAttributedString.Key: Any],
        lastAttrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let font = (firstAttrs[.font] as? PlatformFont) ?? defaultFont()
        let textColor = (firstAttrs[.foregroundColor] as? PlatformColor) ?? defaultTextColor()
        let backgroundColor = (firstAttrs[.backgroundColor] as? PlatformColor) ?? defaultBackgroundColor()
        let borderColor = defaultBorderColor()

        let firstParagraphStyle = firstAttrs[.paragraphStyle] as? NSParagraphStyle
        let lastParagraphStyle = lastAttrs[.paragraphStyle] as? NSParagraphStyle
        let paragraphStyle = mergedParagraphStyle(first: firstParagraphStyle, last: lastParagraphStyle)
        let lineSpacing = paragraphStyle.lineSpacing

        let attachment = CodeBlockAttachment(
            code: code,
            font: font,
            textColor: textColor,
            backgroundColor: backgroundColor,
            borderColor: borderColor,
            lineSpacing: lineSpacing,
            contentInsets: defaultInsets()
        )

        let attrs = sanitizedAttributes(from: firstAttrs, paragraphStyle: paragraphStyle)
        let attachmentString = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: attachment)
        )
        attachmentString.addAttributes(attrs, range: NSRange(location: 0, length: attachmentString.length))
        return attachmentString
    }

    private static func makeHorizontalRuleAttachment(
        paragraphStyle: NSParagraphStyle,
        attrs: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let attachment = HorizontalRuleAttachment(
            lineColor: platformColor(DesignTokens.Colors.border),
            lineHeight: 1
        )
        let attachmentString = NSMutableAttributedString(
            attributedString: NSAttributedString(attachment: attachment)
        )
        let hrAttrs = horizontalRuleAttributes(from: attrs, paragraphStyle: paragraphStyle)
        attachmentString.addAttributes(hrAttrs, range: NSRange(location: 0, length: attachmentString.length))
        return attachmentString
    }

    private static func mergedParagraphStyle(first: NSParagraphStyle?, last: NSParagraphStyle?) -> NSParagraphStyle {
        let base = (first?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        base.paragraphSpacingBefore = first?.paragraphSpacingBefore ?? 0
        base.paragraphSpacing = last?.paragraphSpacing ?? first?.paragraphSpacing ?? 0
        base.lineSpacing = first?.lineSpacing ?? last?.lineSpacing ?? 0
        base.headIndent = 0
        base.firstLineHeadIndent = 0
        base.tailIndent = 0
        return base
    }

    private static func sanitizedAttributes(
        from attrs: [NSAttributedString.Key: Any],
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var result = attrs
        result[NSAttributedString.Key(BlockKindAttribute.name)] = nil
        result[NSAttributedString.Key(ListDepthAttribute.name)] = nil
        result[NSAttributedString.Key(CodeLanguageAttribute.name)] = nil
        result[NSAttributedString.Key(InlineMarkerAttribute.name)] = nil
        result[NSAttributedString.Key(ListMarkerAttribute.name)] = nil
        result[.backgroundColor] = nil
        result[.foregroundColor] = nil
        result[.paragraphStyle] = paragraphStyle
        return result
    }

    private static func horizontalRuleAttributes(
        from attrs: [NSAttributedString.Key: Any],
        paragraphStyle: NSParagraphStyle
    ) -> [NSAttributedString.Key: Any] {
        var result = attrs
        result[NSAttributedString.Key(BlockKindAttribute.name)] = BlockKind.horizontalRule
        result[NSAttributedString.Key(ListDepthAttribute.name)] = nil
        result[NSAttributedString.Key(CodeLanguageAttribute.name)] = nil
        result[NSAttributedString.Key(InlineMarkerAttribute.name)] = nil
        result[NSAttributedString.Key(ListMarkerAttribute.name)] = nil
        result[.backgroundColor] = nil
        result[.foregroundColor] = nil
        result[.paragraphStyle] = paragraphStyle
        return result
    }

    private static func safeAttributes(at index: Int, in text: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard text.length > 0 else { return [:] }
        let safeIndex = max(0, min(index, text.length - 1))
        return text.attributes(at: safeIndex, effectiveRange: nil)
    }

    private static func lineRanges(in string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        let length = string.length
        var start = 0
        while start <= length {
            let search = NSRange(location: start, length: length - start)
            let newlineRange = string.range(of: "\n", options: [], range: search)
            if newlineRange.location == NSNotFound {
                ranges.append(NSRange(location: start, length: length - start))
                break
            } else {
                ranges.append(NSRange(location: start, length: newlineRange.location - start))
                start = newlineRange.location + newlineRange.length
                if start == length {
                    ranges.append(NSRange(location: start, length: 0))
                    break
                }
            }
        }
        return ranges
    }

    private static func blockKind(in lineRange: NSRange, in text: NSAttributedString) -> BlockKind? {
        guard text.length > 0 else { return nil }
        let key = NSAttributedString.Key(BlockKindAttribute.name)
        let start = max(0, min(lineRange.location, text.length - 1))
        if let kind = text.attribute(key, at: start, effectiveRange: nil) as? BlockKind {
            return kind
        }
        let lastLocation = min(lineRange.location + max(0, lineRange.length - 1), text.length - 1)
        if lastLocation != start,
           let kind = text.attribute(key, at: lastLocation, effectiveRange: nil) as? BlockKind {
            return kind
        }
        let afterLocation = min(lineRange.location + lineRange.length, text.length - 1)
        if afterLocation != start,
           afterLocation != lastLocation,
           let kind = text.attribute(key, at: afterLocation, effectiveRange: nil) as? BlockKind {
            return kind
        }
        return nil
    }

    private static func isThematicBreakLine(
        _ lineRange: NSRange,
        blockKind: BlockKind?,
        string: NSString
    ) -> Bool {
        if blockKind == .horizontalRule {
            return true
        }
        let trimmed = string.substring(with: lineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private static func shouldIncludeInCodeBlock(
        at index: Int,
        lineRanges: [NSRange],
        source: NSAttributedString
    ) -> Bool {
        let range = lineRanges[index]
        if blockKind(in: range, in: source) == .codeBlock {
            return true
        }
        guard range.length == 0 else { return false }
        let nextKind = nextNonEmptyBlockKind(startingAt: index + 1, lineRanges: lineRanges, source: source)
        return nextKind == .codeBlock || nextKind == nil
    }

    private static func nextNonEmptyBlockKind(
        startingAt index: Int,
        lineRanges: [NSRange],
        source: NSAttributedString
    ) -> BlockKind? {
        guard index < lineRanges.count else { return nil }
        for lineIndex in index..<lineRanges.count where lineRanges[lineIndex].length > 0 {
            return blockKind(in: lineRanges[lineIndex], in: source)
        }
        return nil
    }

    private static func firstAttributedLineIndex(
        in range: Range<Int>,
        lineRanges: [NSRange],
        source: NSAttributedString
    ) -> Int? {
        for index in range {
            let lineRange = lineRanges[index]
            if lineRange.length == 0 { continue }
            if blockKind(in: lineRange, in: source) == .codeBlock {
                return index
            }
        }
        return nil
    }

    private static func lastAttributedLineIndex(
        in range: Range<Int>,
        lineRanges: [NSRange],
        source: NSAttributedString
    ) -> Int? {
        for index in range.reversed() {
            let lineRange = lineRanges[index]
            if lineRange.length == 0 { continue }
            if blockKind(in: lineRange, in: source) == .codeBlock {
                return index
            }
        }
        return nil
    }

    private static func defaultFont() -> PlatformFont {
#if os(iOS)
        UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
#else
        NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
#endif
    }

    private static func platformColor(_ color: Color) -> PlatformColor {
#if os(iOS)
        UIColor(color)
#else
        NSColor(color)
#endif
    }

    private static func defaultTextColor() -> PlatformColor {
        platformColor(DesignTokens.Colors.textPrimary)
    }

    private static func defaultBackgroundColor() -> PlatformColor {
        platformColor(DesignTokens.Colors.muted)
    }

    private static func defaultBorderColor() -> PlatformColor {
        platformColor(DesignTokens.Colors.border)
    }

    private static func defaultInsets() -> PlatformEdgeInsets {
#if os(iOS)
        UIEdgeInsets(
            top: DesignTokens.Spacing.md,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.md,
            right: DesignTokens.Spacing.md
        )
#else
        NSEdgeInsets(
            top: DesignTokens.Spacing.md,
            left: DesignTokens.Spacing.md,
            bottom: DesignTokens.Spacing.md,
            right: DesignTokens.Spacing.md
        )
#endif
    }
}
