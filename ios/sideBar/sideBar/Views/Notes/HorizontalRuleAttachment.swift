import Foundation
import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
final class HorizontalRuleAttachment: NSTextAttachment {
    static let fileType = "com.ai.sidebar.horizontalrule"

    var lineColor: PlatformColor
    var lineHeight: CGFloat
    var horizontalInset: CGFloat

    init(lineColor: PlatformColor, lineHeight: CGFloat = 1, horizontalInset: CGFloat = 0) {
        self.lineColor = lineColor
        self.lineHeight = max(1, lineHeight)
        self.horizontalInset = max(0, horizontalInset)
        super.init(data: nil, ofType: Self.fileType)
        HorizontalRuleAttachment.registerViewProvider()
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
    }

    required init?(coder: NSCoder) {
        self.lineColor = Self.platformColor(DesignTokens.Colors.border)
        self.lineHeight = 1
        self.horizontalInset = 0
        super.init(coder: coder)
        HorizontalRuleAttachment.registerViewProvider()
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
        let height = max(1, lineHeight)
        let width = proposedLineFragment.width + (horizontalInset * 2)
        let scale = effectiveScale(textContainer: textContainer)
        let alignedWidth = (width * scale).rounded() / scale
        let alignedX = (-horizontalInset * scale).rounded() / scale
        return CGRect(x: alignedX, y: 0, width: alignedWidth, height: height)
    }

    private static let didRegisterViewProvider: Void = {
        NSTextAttachment.registerViewProviderClass(
            HorizontalRuleAttachmentViewProvider.self,
            forFileType: HorizontalRuleAttachment.fileType
        )
    }()

    private static func registerViewProvider() {
        _ = didRegisterViewProvider
    }

    private static func platformColor(_ color: Color) -> PlatformColor {
#if os(iOS)
        UIColor(color)
#else
        NSColor(color)
#endif
    }

    private func effectiveScale(textContainer: NSTextContainer?) -> CGFloat {
#if os(iOS)
        return 1
#else
        return textContainer?.textView?.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
#endif
    }
}

@available(iOS 26.0, macOS 26.0, *)
final class HorizontalRuleAttachmentViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? HorizontalRuleAttachment else {
            self.view = PlatformView()
            return
        }
        self.view = HorizontalRuleView(
            lineColor: attachment.lineColor,
            lineHeight: attachment.lineHeight
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
final class HorizontalRuleView: PlatformView {
    private let lineColor: PlatformColor

    init(lineColor: PlatformColor, lineHeight: CGFloat) {
        self.lineColor = lineColor
        super.init(frame: .zero)
#if os(iOS)
        backgroundColor = lineColor
        isOpaque = true
#else
        wantsLayer = true
        layer?.backgroundColor = lineColor.cgColor
#endif
    }

    required init?(coder: NSCoder) {
        self.lineColor = PlatformColor.clear
        super.init(coder: coder)
#if os(iOS)
        backgroundColor = lineColor
        isOpaque = false
#else
        wantsLayer = true
        layer?.backgroundColor = lineColor.cgColor
#endif
    }
}
