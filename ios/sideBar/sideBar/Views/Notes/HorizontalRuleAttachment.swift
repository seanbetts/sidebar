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

    init(lineColor: PlatformColor, lineHeight: CGFloat = 1) {
        self.lineColor = lineColor
        self.lineHeight = max(1, lineHeight)
        super.init(data: nil, ofType: Self.fileType)
        HorizontalRuleAttachment.registerViewProvider()
        allowsTextAttachmentView = true
        lineLayoutPadding = 0
    }

    required init?(coder: NSCoder) {
        self.lineColor = Self.platformColor(DesignTokens.Colors.border)
        self.lineHeight = 1
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
        return CGRect(x: 0, y: 0, width: proposedLineFragment.width, height: height)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        let height = max(1, lineHeight)
        return CGRect(x: 0, y: 0, width: lineFrag.width, height: height)
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
    private let lineLayer = CALayer()
    private let lineHeight: CGFloat

    init(lineColor: PlatformColor, lineHeight: CGFloat) {
        self.lineHeight = max(1, lineHeight)
        super.init(frame: .zero)
#if os(iOS)
        backgroundColor = .clear
        layer.addSublayer(lineLayer)
#else
        wantsLayer = true
        layer?.addSublayer(lineLayer)
#endif
        lineLayer.backgroundColor = lineColor.cgColor
    }

    required init?(coder: NSCoder) {
        self.lineHeight = 1
        super.init(coder: coder)
#if os(iOS)
        backgroundColor = .clear
        layer.addSublayer(lineLayer)
#else
        wantsLayer = true
        layer?.addSublayer(lineLayer)
#endif
        lineLayer.backgroundColor = PlatformColor.clear.cgColor
    }

#if os(iOS)
    override func layoutSubviews() {
        super.layoutSubviews()
        updateLineFrame()
    }
#else
    override func layout() {
        super.layout()
        updateLineFrame()
    }
#endif

    private func updateLineFrame() {
        let height = max(1, lineHeight)
        let lineY = (bounds.height - height) / 2
        lineLayer.frame = CGRect(x: 0, y: lineY, width: bounds.width, height: height)
    }
}
