import SwiftUI
#if os(iOS)
@preconcurrency import UIKit
#elseif os(macOS)
@preconcurrency import AppKit
#endif

@available(iOS 26.0, macOS 26.0, *)
enum NoteTextStyleTypography {
    private struct Metrics {
        let scale: CGFloat
        let weight: Font.Weight
        let platformWeight: NotePlatformFont.Weight
    }

    static func pointSize(for style: NoteTextStyle, baseFontSize: CGFloat) -> CGFloat {
        baseFontSize * metrics(for: style).scale
    }

    static func fontWeight(for style: NoteTextStyle) -> Font.Weight {
        metrics(for: style).weight
    }

    static func platformWeight(for style: NoteTextStyle) -> NotePlatformFont.Weight {
        metrics(for: style).platformWeight
    }

    static func font(for style: NoteTextStyle, baseFontSize: CGFloat) -> Font {
        let metrics = metrics(for: style)
        return .system(size: baseFontSize * metrics.scale, weight: metrics.weight)
    }

    static func platformFont(for style: NoteTextStyle, baseFontSize: CGFloat) -> NotePlatformFont {
        let metrics = metrics(for: style)
        #if os(iOS)
        return UIFont.systemFont(ofSize: baseFontSize * metrics.scale, weight: metrics.platformWeight)
        #elseif os(macOS)
        return NSFont.systemFont(ofSize: baseFontSize * metrics.scale, weight: metrics.platformWeight)
        #endif
    }

    static func platformFont(
        for blockType: NotesSemanticDocument.BlockType,
        baseFontSize: CGFloat
    ) -> NotePlatformFont? {
        guard let style = NoteTextStyle(blockType: blockType) else { return nil }
        return platformFont(for: style, baseFontSize: baseFontSize)
    }

    private static func metrics(for style: NoteTextStyle) -> Metrics {
        switch style {
        case .title:
            return Metrics(scale: 1.75, weight: .bold, platformWeight: .bold)
        case .heading:
            return Metrics(scale: 1.4, weight: .bold, platformWeight: .bold)
        case .subheading:
            return Metrics(scale: 1.15, weight: .bold, platformWeight: .bold)
        case .body:
            return Metrics(scale: 1.0, weight: .regular, platformWeight: .regular)
        }
    }
}
