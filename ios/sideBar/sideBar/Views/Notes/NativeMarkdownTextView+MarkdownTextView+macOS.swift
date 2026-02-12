import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

@available(iOS 26.0, macOS 26.0, *)
final class MarkdownTextView: NSTextView {
    private static let inlineMarkerKey = NSAttributedString.Key("sideBar.inlineMarker")
    private static let listMarkerKey = NSAttributedString.Key("sideBar.listMarker")

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let location = selectedRange().location
        let adjustedRect = clampedInsertionRect(rect, utf16Offset: location)
        super.drawInsertionPoint(in: adjustedRect, color: color, turnedOn: flag)
    }

    func refreshTypingAttributesForSelection() {
        guard isEditable else { return }
        typingAttributes = preferredTypingAttributes(atUTF16Offset: selectedRange().location)
    }

    private func clampedInsertionRect(_ rect: NSRect, utf16Offset: Int) -> NSRect {
        guard rect.height > 0 else { return rect }
        let targetHeight = preferredCaretHeight(atUTF16Offset: utf16Offset)
        guard targetHeight > 0 else { return rect }
        guard rect.height > targetHeight + 1 else { return rect }
        var adjusted = rect
        adjusted.origin.y += (rect.height - targetHeight) / 2
        adjusted.size.height = targetHeight
        return adjusted
    }

    private func preferredCaretHeight(atUTF16Offset offset: Int) -> CGFloat {
        if let font = nearestVisibleFont(atUTF16Offset: offset) {
            return platformLineHeight(for: font)
        }
        if let font = typingAttributes[.font] as? NSFont {
            return platformLineHeight(for: font)
        }
        if let font = self.font {
            return platformLineHeight(for: font)
        }
        return platformLineHeight(for: NSFont.systemFont(ofSize: 16))
    }

    private func preferredTypingAttributes(atUTF16Offset offset: Int) -> [NSAttributedString.Key: Any] {
        var attributes = sanitizedTypingAttributes(from: typingAttributes)

        if let nearest = nearestVisibleAttributes(atUTF16Offset: offset) {
            let sanitized = sanitizedTypingAttributes(from: nearest)
            if !sanitized.isEmpty {
                attributes.merge(sanitized) { _, new in new }
            }
        }

        if attributes[.font] == nil {
            attributes[.font] = self.font ?? NSFont.systemFont(ofSize: 16)
        }

        return attributes
    }

    private func nearestVisibleFont(atUTF16Offset offset: Int) -> NSFont? {
        guard let attributes = nearestVisibleAttributes(atUTF16Offset: offset) else { return nil }
        return attributes[.font] as? NSFont
    }

    private func nearestVisibleAttributes(atUTF16Offset offset: Int) -> [NSAttributedString.Key: Any]? {
        let length = textStorage?.length ?? 0
        guard length > 0 else { return nil }
        let clamped = min(max(offset, 0), length)
        let searchLimit = min(length, 64)

        for step in 0...searchLimit {
            let before = clamped - 1 - step
            if before >= 0, let textStorage {
                let attributes = textStorage.attributes(at: before, effectiveRange: nil)
                if !isHiddenMarkerAttributes(attributes) {
                    return attributes
                }
            }

            let after = clamped + step
            if after < length, let textStorage {
                let attributes = textStorage.attributes(at: after, effectiveRange: nil)
                if !isHiddenMarkerAttributes(attributes) {
                    return attributes
                }
            }
        }

        return nil
    }

    private func isHiddenMarkerAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        if (attributes[Self.inlineMarkerKey] as? Bool) == true || (attributes[Self.listMarkerKey] as? Bool) == true {
            return true
        }
        if let font = attributes[.font] as? NSFont, font.pointSize <= 1 {
            return true
        }
        if let color = attributes[.foregroundColor] as? NSColor {
            let alpha = color.usingColorSpace(.deviceRGB)?.alphaComponent ?? color.alphaComponent
            if alpha <= 0.01 {
                return true
            }
        }
        return false
    }

    private func sanitizedTypingAttributes(
        from attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        let allowedKeys: [NSAttributedString.Key] = [
            .font,
            .foregroundColor,
            .backgroundColor,
            .paragraphStyle,
            .underlineStyle,
            .strikethroughStyle,
            .link,
            .kern
        ]
        var sanitized: [NSAttributedString.Key: Any] = [:]
        for key in allowedKeys {
            if let value = attributes[key] {
                sanitized[key] = value
            }
        }
        return sanitized
    }

    private func platformLineHeight(for font: NSFont) -> CGFloat {
        font.ascender - font.descender + font.leading
    }

    override func draw(_ dirtyRect: NSRect) {
        drawBackgroundDecorations(in: dirtyRect)
        super.draw(dirtyRect)
        drawForegroundDecorations(in: dirtyRect)
    }

    private struct LineData {
        let range: NSRange
        let text: String
        let blockKind: BlockKind?
        let listDepth: Int
        let tableInfo: (isHeader: Bool, rowIndex: Int?)?
        let rects: [CGRect]
    }

    private func drawBackgroundDecorations(in rect: CGRect) {
        guard let textContainer else { return }
        let textStorage = self.textStorage ?? NSTextStorage()
        let string = textStorage.string as NSString
        let origin = CGPoint(
            x: textContainerOrigin.x - bounds.origin.x,
            y: textContainerOrigin.y - bounds.origin.y
        )
        let lines = lineRanges(in: string).compactMap { lineRange -> LineData? in
            let lineText = string.substring(with: lineRange)
            guard lineRange.length > 0 || !lineText.isEmpty else { return nil }
            let blockKind = blockKind(in: lineRange, in: textStorage)
            let listDepth = listDepth(at: lineRange.location, in: textStorage) ?? 1
            let tableInfo = tableRowInfo(in: textStorage, lineRange: lineRange)
            let rects = lineRects(for: lineRange, in: textContainer).map { rect in
                rect.offsetBy(dx: origin.x, dy: origin.y)
            }
            return LineData(
                range: lineRange,
                text: lineText,
                blockKind: blockKind,
                listDepth: listDepth,
                tableInfo: tableInfo,
                rects: rects
            )
        }

	        drawTableBackgrounds(lines: lines)
	        drawCodeBlockContainers(lines: lines)
	        drawBlockquoteBars(lines: lines)
	        drawTableBorders(lines: lines)
	    }

	    private func drawForegroundDecorations(in rect: CGRect) {
	    }

	    private func drawBlockquoteBars(lines: [LineData]) {
	        let barWidth: CGFloat = 3
	        let barColor = NSColor(DesignTokens.Colors.border)
        var index = 0
        while index < lines.count {
            guard lines[index].blockKind == .blockquote else {
                index += 1
                continue
            }
            var endIndex = index
            while endIndex + 1 < lines.count, lines[endIndex + 1].blockKind == .blockquote {
                endIndex += 1
            }
            let rects = lines[index...endIndex].flatMap { $0.rects }
            if let union = unionRect(rects) {
                let barRect = CGRect(x: union.minX, y: union.minY, width: barWidth, height: union.height)
                barColor.setFill()
                NSBezierPath(rect: barRect).fill()
            }
            index = endIndex + 1
        }
    }

    private func drawCodeBlockContainers(lines: [LineData]) {
        let strokeColor = NSColor(DesignTokens.Colors.border)
        let cornerRadius: CGFloat = 10
        var index = 0
        while index < lines.count {
            guard lines[index].blockKind == .codeBlock else {
                index += 1
                continue
            }
            var endIndex = index
            while endIndex + 1 < lines.count, lines[endIndex + 1].blockKind == .codeBlock {
                endIndex += 1
            }
            let rects = lines[index...endIndex].flatMap { $0.rects }
            if let union = unionRect(rects) {
                let fillColor = codeBlockBackgroundColor(for: lines[index]) ?? NSColor(DesignTokens.Colors.muted)
                let padded = union.insetBy(dx: 0, dy: -DesignTokens.Spacing.md)
                let path = NSBezierPath(roundedRect: padded, xRadius: cornerRadius, yRadius: cornerRadius)
                fillColor.setFill()
                path.fill()
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            index = endIndex + 1
        }
    }

    private func drawTableBackgrounds(lines: [LineData]) {
        let tablePaddingX: CGFloat = 12
        for line in lines {
            guard let info = line.tableInfo, let rect = unionRect(line.rects) else { continue }
            let background: NSColor
            if info.isHeader {
                background = NSColor(DesignTokens.Colors.muted)
            } else if let rowIndex = info.rowIndex, rowIndex % 2 == 1 {
                background = NSColor(DesignTokens.Colors.muted.opacity(0.4))
            } else {
                background = NSColor(DesignTokens.Colors.background)
            }
            let paddedRect = rect.insetBy(dx: -tablePaddingX, dy: 0)
            background.setFill()
            NSBezierPath(rect: paddedRect).fill()
        }
    }

    private func drawTableBorders(lines: [LineData]) {
        let strokeColor = NSColor(DesignTokens.Colors.border)
        let tablePaddingX: CGFloat = 12
        var index = 0
        while index < lines.count {
            guard lines[index].tableInfo != nil else {
                index += 1
                continue
            }
            var endIndex = index
            while endIndex + 1 < lines.count, lines[endIndex + 1].tableInfo != nil {
                endIndex += 1
            }
            let rects = lines[index...endIndex].flatMap { $0.rects }
            guard let rawRect = unionRect(rects) else {
                index = endIndex + 1
                continue
            }
            let tableRect = rawRect.insetBy(dx: -tablePaddingX, dy: 0)
            let borderPath = NSBezierPath(rect: tableRect)
            strokeColor.setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()

            for rowIndex in index...endIndex {
                guard let rowRect = unionRect(lines[rowIndex].rects) else { continue }
                let rowMaxY = rowRect.maxY
                let path = NSBezierPath()
                path.move(to: CGPoint(x: tableRect.minX, y: rowMaxY))
                path.line(to: CGPoint(x: tableRect.maxX, y: rowMaxY))
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            let headerRange = lines[index].range
            let tabPositions = tabStopsXPositions(in: headerRange).map { $0 + tableRect.minX }
            for tabPositionX in tabPositions {
                let path = NSBezierPath()
                path.move(to: CGPoint(x: tabPositionX, y: tableRect.minY))
                path.line(to: CGPoint(x: tabPositionX, y: tableRect.maxY))
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            index = endIndex + 1
        }
    }

    private func lineRanges(in string: NSString) -> [NSRange] {
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

    private func lineRects(for lineRange: NSRange, in textContainer: NSTextContainer) -> [CGRect] {
        guard let layoutManager = self.layoutManager else { return [] }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rects: [CGRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            rects.append(rect)
        }
        return rects
    }

    private func blockKind(in lineRange: NSRange, in text: NSAttributedString) -> BlockKind? {
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

    private func listDepth(at location: Int, in text: NSAttributedString) -> Int? {
        guard location < text.length else { return nil }
        let key = NSAttributedString.Key(ListDepthAttribute.name)
        return text.attribute(key, at: location, effectiveRange: nil) as? Int
    }

    private func tableRowInfo(in text: NSAttributedString, lineRange: NSRange) -> (isHeader: Bool, rowIndex: Int?)? {
        var isHeader = false
        var rowIndex: Int?
        var found = false
        let key = NSAttributedString.Key("NSPresentationIntent")
        text.enumerateAttribute(key, in: lineRange, options: []) { value, _, _ in
            guard let intent = value as? PresentationIntent else { return }
            for component in intent.components {
                switch component.kind {
                case .tableHeaderRow:
                    isHeader = true
                    rowIndex = 0
                    found = true
                case .tableRow(let index):
                    rowIndex = index
                    found = true
                default:
                    break
                }
            }
        }
        return found ? (isHeader, rowIndex) : nil
    }

    private func tabStopsXPositions(in lineRange: NSRange) -> [CGFloat] {
        guard let layoutManager = self.layoutManager else { return [] }
        let string = (textStorage?.string ?? "") as NSString
        let end = lineRange.location + lineRange.length
        var positions: [CGFloat] = []
        var index = lineRange.location
        while index < end {
            if string.character(at: index) == 9 {
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
                let location = layoutManager.location(forGlyphAt: glyphIndex)
                positions.append(location.x)
            }
            index += 1
        }
        return positions
    }

    private func unionRect(_ rects: [CGRect]) -> CGRect? {
        guard var rect = rects.first else { return nil }
        for next in rects.dropFirst() {
            rect = rect.union(next)
        }
        return rect
    }

    private func codeBlockBackgroundColor(for line: LineData) -> NSColor? {
        guard let textStorage, line.range.location < textStorage.length else { return nil }
        if let color = textStorage.attribute(.backgroundColor, at: line.range.location, effectiveRange: nil) as? NSColor {
            return color
        }
        return nil
    }
}
#endif
