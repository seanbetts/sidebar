import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
private func displayText(for text: AttributedString, isEditable: Bool) -> NSAttributedString {
    if isEditable {
        return CodeBlockAttachmentBuilder.applyStrikethroughAttributes(from: text, to: NSAttributedString(text))
    }
    return CodeBlockAttachmentBuilder.displayText(from: text)
}

#if os(iOS)
@available(iOS 26.0, macOS 26.0, *)
struct NativeMarkdownTextView: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var selection: AttributedTextSelection
    var isEditable: Bool = true
    var isSelectable: Bool = true
    var syncSelection: Bool = true
    var isScrollEnabled: Bool = true
    var onTap: (() -> Void)?

    func makeUIView(context: Context) -> UITextView {
        let textView = MarkdownTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = isScrollEnabled
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.attributedText = displayText(for: text, isEditable: isEditable)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        textView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isUpdating = true
        textView.isEditable = isEditable
        textView.isSelectable = isSelectable
        textView.isScrollEnabled = isScrollEnabled
        context.coordinator.tapRecognizer?.isEnabled = onTap != nil
        let nsText = displayText(for: text, isEditable: isEditable)
        if !textView.attributedText.isEqual(to: nsText) {
            textView.attributedText = nsText
            textView.setNeedsDisplay()
        }
        if syncSelection {
            let desiredRange = nsRange(from: selection, in: text)
            if textView.selectedRange != desiredRange {
                textView.selectedRange = desiredRange
            }
        }
        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeMarkdownTextView
        var isUpdating = false
        var tapRecognizer: UITapGestureRecognizer?

        init(_ parent: NativeMarkdownTextView) {
            self.parent = parent
        }

        @objc func handleTap() {
            parent.onTap?()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isUpdating else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = AttributedString(textView.attributedText)
                textView.setNeedsDisplay()
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = selectionFromRange(textView.selectedRange, in: self.parent.text)
                textView.setNeedsDisplay()
            }
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
private final class MarkdownTextView: UITextView {
    override func draw(_ rect: CGRect) {
        drawBackgroundDecorations(in: rect)
        super.draw(rect)
        drawForegroundDecorations(in: rect)
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
        let textContainer = self.textContainer
        let textStorage = self.textStorage
        let string = textStorage.string as NSString
        let origin = CGPoint(
            x: textContainerInset.left - contentOffset.x,
            y: textContainerInset.top - contentOffset.y
        )
        let lines = lineRanges(in: string).compactMap { lineRange -> LineData? in
            let lineText = string.substring(with: lineRange)
            guard lineRange.length > 0 || !lineText.isEmpty else { return nil }
            let blockKind = blockKind(at: lineRange.location, in: textStorage)
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
        drawHorizontalRules(lines: lines)
        drawTableBorders(lines: lines)
    }

    private func drawForegroundDecorations(in rect: CGRect) {
    }

    private func drawBlockquoteBars(lines: [LineData]) {
        let barWidth: CGFloat = 3
        let barColor = UIColor(DesignTokens.Colors.border)
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
                UIBezierPath(rect: barRect).fill()
            }
            index = endIndex + 1
        }
    }

    private func drawCodeBlockContainers(lines: [LineData]) {
        let strokeColor = UIColor(DesignTokens.Colors.border)
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
                let fillColor = codeBlockBackgroundColor(for: lines[index]) ?? UIColor(DesignTokens.Colors.muted)
                let padded = union.insetBy(dx: 0, dy: -DesignTokens.Spacing.md)
                let path = UIBezierPath(roundedRect: padded, cornerRadius: cornerRadius)
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
            let background: UIColor
            if info.isHeader {
                background = UIColor(DesignTokens.Colors.muted)
            } else if let rowIndex = info.rowIndex, rowIndex % 2 == 1 {
                background = UIColor(DesignTokens.Colors.muted.opacity(0.4))
            } else {
                background = UIColor(DesignTokens.Colors.background)
            }
            let paddedRect = rect.insetBy(dx: -tablePaddingX, dy: 0)
            background.setFill()
            UIBezierPath(rect: paddedRect).fill()
        }
    }

    private func drawTableBorders(lines: [LineData]) {
        let strokeColor = UIColor(DesignTokens.Colors.border)
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
            let borderPath = UIBezierPath(rect: tableRect)
            strokeColor.setStroke()
            borderPath.lineWidth = 1
            borderPath.stroke()

            // Horizontal row separators
            for rowIndex in index...endIndex {
                guard let rowRect = unionRect(lines[rowIndex].rects) else { continue }
                let rowMaxY = rowRect.maxY
                let path = UIBezierPath()
                path.move(to: CGPoint(x: tableRect.minX, y: rowMaxY))
                path.addLine(to: CGPoint(x: tableRect.maxX, y: rowMaxY))
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            // Vertical column separators based on tab positions in header row
            let headerRange = lines[index].range
            let tabPositions = tabStopsXPositions(in: headerRange).map { $0 + tableRect.minX }
            for tabPositionX in tabPositions {
                let path = UIBezierPath()
                path.move(to: CGPoint(x: tabPositionX, y: tableRect.minY))
                path.addLine(to: CGPoint(x: tabPositionX, y: tableRect.maxY))
                strokeColor.setStroke()
                path.lineWidth = 1
                path.stroke()
            }

            index = endIndex + 1
        }
    }

    private func drawHorizontalRules(lines: [LineData]) {
        let strokeColor = UIColor(DesignTokens.Colors.border)
        for line in lines where line.blockKind == .horizontalRule {
            guard let rect = unionRect(line.rects) else { continue }
            let midY = rect.midY
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY))
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
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
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rects: [CGRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, _, _ in
            rects.append(rect)
        }
        return rects
    }

    private func blockKind(at location: Int, in text: NSAttributedString) -> BlockKind? {
        guard location < text.length else { return nil }
        let key = NSAttributedString.Key(BlockKindAttribute.name)
        return text.attribute(key, at: location, effectiveRange: nil) as? BlockKind
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
        let string = textStorage.string as NSString
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

    private func codeBlockBackgroundColor(for line: LineData) -> UIColor? {
        guard line.range.location < textStorage.length else { return nil }
        if let color = textStorage.attribute(.backgroundColor, at: line.range.location, effectiveRange: nil) as? UIColor {
            return color
        }
        return nil
    }
}
#elseif os(macOS)
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
        DispatchQueue.main.async {
            context.coordinator.isUpdating = false
        }
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
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                self.parent.text = AttributedString(textView.attributedString())
                textView.needsDisplay = true
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating,
                  let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isUpdating else { return }
                guard self.parent.syncSelection else { return }
                self.parent.selection = selectionFromRange(textView.selectedRange(), in: self.parent.text)
                textView.needsDisplay = true
            }
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
            let blockKind = blockKind(at: lineRange.location, in: textStorage)
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
        drawHorizontalRules(lines: lines)
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

    private func drawHorizontalRules(lines: [LineData]) {
        let strokeColor = NSColor(DesignTokens.Colors.border)
        for line in lines where line.blockKind == .horizontalRule {
            guard let rect = unionRect(line.rects) else { continue }
            let midY = rect.midY
            let path = NSBezierPath()
            path.move(to: CGPoint(x: rect.minX, y: midY))
            path.line(to: CGPoint(x: rect.maxX, y: midY))
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()
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

    private func blockKind(at location: Int, in text: NSAttributedString) -> BlockKind? {
        guard location < text.length else { return nil }
        let key = NSAttributedString.Key(BlockKindAttribute.name)
        return text.attribute(key, at: location, effectiveRange: nil) as? BlockKind
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

@available(iOS 26.0, macOS 26.0, *)
private func nsRange(from selection: AttributedTextSelection, in text: AttributedString) -> NSRange {
    let string = String(text.characters)
    switch selection.indices(in: text) {
    case .insertionPoint(let index):
        let charOffset = text.characters.distance(from: text.startIndex, to: index)
        let stringIndex = string.index(string.startIndex, offsetBy: charOffset)
        let location = stringIndex.utf16Offset(in: string)
        return NSRange(location: location, length: 0)
    case .ranges(let ranges):
        guard let first = ranges.ranges.first else {
            return NSRange(location: 0, length: 0)
        }
        let lowerOffset = text.characters.distance(from: text.startIndex, to: first.lowerBound)
        let upperOffset = text.characters.distance(from: text.startIndex, to: first.upperBound)
        let lowerIndex = string.index(string.startIndex, offsetBy: lowerOffset)
        let upperIndex = string.index(string.startIndex, offsetBy: upperOffset)
        let location = lowerIndex.utf16Offset(in: string)
        let length = upperIndex.utf16Offset(in: string) - location
        return NSRange(location: location, length: max(0, length))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func selectionFromRange(_ range: NSRange, in text: AttributedString) -> AttributedTextSelection {
    let string = String(text.characters)
    let maxLocation = string.utf16.count
    let safeLocation = min(max(0, range.location), maxLocation)
    let safeEnd = min(max(0, range.location + range.length), maxLocation)
    let startIndex = String.Index(utf16Offset: safeLocation, in: string)
    let endIndex = String.Index(utf16Offset: safeEnd, in: string)
    let startOffset = string.distance(from: string.startIndex, to: startIndex)
    let endOffset = string.distance(from: string.startIndex, to: endIndex)
    let start = text.index(text.startIndex, offsetByCharacters: startOffset)
    let end = text.index(text.startIndex, offsetByCharacters: endOffset)
    if start == end {
        return AttributedTextSelection(range: start..<start)
    }
    return AttributedTextSelection(range: start..<end)
}
