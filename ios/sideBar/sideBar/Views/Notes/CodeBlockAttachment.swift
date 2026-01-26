import Foundation
import SwiftUI

#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
typealias PlatformEdgeInsets = UIEdgeInsets
typealias PlatformView = UIView
#else
import AppKit
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
typealias PlatformEdgeInsets = NSEdgeInsets
typealias PlatformView = NSView
#endif

@available(iOS 26.0, macOS 26.0, *)
final class CodeBlockAttachment: NSTextAttachment {
    static let fileType = "com.ai.sidebar.codeblock"

    var code: String
    var font: PlatformFont
    var textColor: PlatformColor
    var backgroundColor: PlatformColor
    var borderColor: PlatformColor
    var lineSpacing: CGFloat
    var contentInsets: PlatformEdgeInsets
    var cornerRadius: CGFloat
    var borderWidth: CGFloat
    var maxLineWidth: CGFloat
    var measuredHeight: CGFloat

    init(
        code: String,
        font: PlatformFont,
        textColor: PlatformColor,
        backgroundColor: PlatformColor,
        borderColor: PlatformColor,
        lineSpacing: CGFloat,
        contentInsets: PlatformEdgeInsets,
        cornerRadius: CGFloat = 10,
        borderWidth: CGFloat = 1
    ) {
        self.code = code
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.borderColor = borderColor
        self.lineSpacing = lineSpacing
        self.contentInsets = contentInsets
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.maxLineWidth = CodeBlockAttachment.longestLineWidth(for: code, font: font)
        self.measuredHeight = CodeBlockAttachment.height(
            for: code,
            font: font,
            lineSpacing: lineSpacing,
            insets: contentInsets
        )
        super.init(data: code.data(using: .utf8), ofType: Self.fileType)
        CodeBlockAttachment.registerViewProvider()
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
    }

    required init?(coder: NSCoder) {
        self.code = ""
#if os(iOS)
        self.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
#else
        self.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
#endif
        self.textColor = CodeBlockAttachment.defaultTextColor()
        self.backgroundColor = CodeBlockAttachment.defaultBackgroundColor()
        self.borderColor = CodeBlockAttachment.defaultBorderColor()
        self.lineSpacing = 0
        self.contentInsets = CodeBlockAttachment.defaultInsets()
        self.cornerRadius = 10
        self.borderWidth = 1
        self.maxLineWidth = 0
        self.measuredHeight = 0
        super.init(coder: coder)
        CodeBlockAttachment.registerViewProvider()
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let width = proposedLineFragment.width
        return CGRect(x: 0, y: 0, width: width, height: measuredHeight)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let width = lineFrag.width
        return CGRect(x: 0, y: 0, width: width, height: measuredHeight)
    }

    private static let didRegisterViewProvider: Void = {
        NSTextAttachment.registerViewProviderClass(
            CodeBlockAttachmentViewProvider.self,
            forFileType: CodeBlockAttachment.fileType
        )
    }()

    private static func registerViewProvider() {
        _ = didRegisterViewProvider
    }

    private static func longestLineWidth(for code: String, font: PlatformFont) -> CGFloat {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var maxWidth: CGFloat = 1
        for line in lines {
            let width = (line as NSString).size(withAttributes: attributes).width
            maxWidth = max(maxWidth, ceil(width))
        }
        return maxWidth
    }

    private static func height(
        for code: String,
        font: PlatformFont,
        lineSpacing: CGFloat,
        insets: PlatformEdgeInsets
    ) -> CGFloat {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(1, lines.count)
        let lineHeight = platformLineHeight(for: font)
        let spacing = CGFloat(max(0, lineCount - 1)) * lineSpacing
        return (CGFloat(lineCount) * lineHeight) + spacing + insets.top + insets.bottom
    }

    private static func platformLineHeight(for font: PlatformFont) -> CGFloat {
#if os(iOS)
        font.lineHeight
#else
        font.ascender - font.descender + font.leading
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

@available(iOS 26.0, macOS 26.0, *)
final class CodeBlockAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? CodeBlockAttachment else {
            self.view = PlatformView()
            return
        }
#if os(iOS)
        self.view = makeTextView(for: attachment)
#else
        self.view = makeScrollView(for: attachment)
#endif
    }

#if os(iOS)
    private func makeTextView(for attachment: CodeBlockAttachment) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.showsHorizontalScrollIndicator = true
        textView.showsVerticalScrollIndicator = false
        textView.alwaysBounceHorizontal = true
        textView.alwaysBounceVertical = false
        textView.backgroundColor = attachment.backgroundColor
        textView.clipsToBounds = true
        textView.layer.cornerRadius = attachment.cornerRadius
        textView.layer.borderWidth = attachment.borderWidth
        textView.layer.borderColor = attachment.borderColor.cgColor
        textView.textContainerInset = attachment.contentInsets
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byClipping
        textView.textContainer.widthTracksTextView = false
        let contentWidth = attachment.maxLineWidth + attachment.contentInsets.left + attachment.contentInsets.right
        textView.textContainer.size = CGSize(width: max(contentWidth, 1), height: .greatestFiniteMagnitude)
        textView.attributedText = codeAttributedString(for: attachment)
        return textView
    }
#else
    private func makeScrollView(for attachment: CodeBlockAttachment) -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = attachment.backgroundColor.cgColor
        scrollView.layer?.cornerRadius = attachment.cornerRadius
        scrollView.layer?.borderWidth = attachment.borderWidth
        scrollView.layer?.borderColor = attachment.borderColor.cgColor
        scrollView.layer?.masksToBounds = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(
            width: attachment.contentInsets.left,
            height: attachment.contentInsets.top
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = false
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineBreakMode = .byClipping
        let contentWidth = attachment.maxLineWidth + attachment.contentInsets.left + attachment.contentInsets.right
        textView.textContainer?.size = NSSize(width: max(contentWidth, 1), height: .greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(codeAttributedString(for: attachment))
        scrollView.documentView = textView
        return scrollView
    }
#endif

    private func codeAttributedString(for attachment: CodeBlockAttachment) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = attachment.lineSpacing
        let attributes: [NSAttributedString.Key: Any] = [
            .font: attachment.font,
            .foregroundColor: attachment.textColor,
            .paragraphStyle: paragraphStyle
        ]
        return NSAttributedString(string: attachment.code, attributes: attributes)
    }
}
