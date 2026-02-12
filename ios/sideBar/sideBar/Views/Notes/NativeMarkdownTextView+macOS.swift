import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: NSViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsImageEditing = false
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textStorage?.setAttributedString(displayText(for: text, isEditable: isEditable))
        let tap = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        textView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = isScrollEnabled
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        scrollView.hasVerticalScroller = isScrollEnabled
        context.coordinator.tapRecognizer?.isEnabled = onTap != nil
        let nsText = displayText(for: text, isEditable: isEditable)
        if !(textView.attributedString().isEqual(to: nsText)) {
            textView.textStorage?.setAttributedString(nsText)
            textView.needsDisplay = true
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if textView.selectedRange() != desiredRange {
                textView.setSelectedRange(desiredRange)
            }
        }
        context.coordinator.isUpdating = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: NSClickGestureRecognizer?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            let snapshot = AttributedString(textView.attributedString())
            if parent.text != snapshot {
                parent.text = snapshot
            }
            if parent.syncSelection {
                parent.selection = selectionFromRange(textView.selectedRange(), in: snapshot)
            }
            textView.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            guard parent.syncSelection else { return }
            let snapshot = AttributedString(textView.attributedString())
            if parent.text != snapshot {
                parent.text = snapshot
            }
            parent.selection = selectionFromRange(textView.selectedRange(), in: snapshot)
            textView.needsDisplay = true
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class MarkdownTextView: NSTextView {
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
