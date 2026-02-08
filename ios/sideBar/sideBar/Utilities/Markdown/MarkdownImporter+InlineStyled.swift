@preconcurrency import Foundation
import Markdown
import sideBarShared
import SwiftUI

extension MarkdownToAttributedStringWalker {
    func inlineStyledAttributedString(
        for markup: Markup,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString {
        if let emphasis = markup as? Emphasis {
            return emphasisAttributedString(emphasis, intents: intents, isStrikethrough: isStrikethrough)
        }
        if let strong = markup as? Strong {
            return strongAttributedString(strong, intents: intents, isStrikethrough: isStrikethrough)
        }
        if let strike = markup as? Strikethrough {
            return strikethroughAttributedString(strike, intents: intents)
        }
        if let code = markup as? InlineCode {
            return inlineCodeAttributedString(code, intents: intents, isStrikethrough: isStrikethrough)
        }
        if let link = markup as? Markdown.Link {
            return inlineLinkAttributedString(link, intents: intents, isStrikethrough: isStrikethrough)
        }
        if let image = markup as? Markdown.Image {
            return inlineImageAttributedString(image)
        }
        if let html = markup as? Markdown.InlineHTML {
            return AttributedString(html.rawHTML)
        }
        var fallback = AttributedString()
        for child in markup.children {
            fallback.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: isStrikethrough))
        }
        return fallback
    }

    private func emphasisAttributedString(
        _ emphasis: Emphasis,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString {
        var inner = AttributedString()
        let mergedIntents = intents.union(.emphasized)
        for child in emphasis.children {
            inner.append(inlineAttributedString(for: child, intents: mergedIntents, isStrikethrough: isStrikethrough))
        }
        return wrapInlineMarkers(inner, prefix: "*", suffix: "*")
    }

    private func strongAttributedString(
        _ strong: Strong,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString {
        var inner = AttributedString()
        let mergedIntents = intents.union(.stronglyEmphasized)
        for child in strong.children {
            inner.append(inlineAttributedString(for: child, intents: mergedIntents, isStrikethrough: isStrikethrough))
        }
        return wrapInlineMarkers(inner, prefix: "**", suffix: "**")
    }

    private func strikethroughAttributedString(
        _ strike: Strikethrough,
        intents: InlinePresentationIntent
    ) -> AttributedString {
        var inner = AttributedString()
        for child in strike.children {
            inner.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: true))
        }
        return wrapInlineMarkers(inner, prefix: "~~", suffix: "~~")
    }

    private func inlineCodeAttributedString(
        _ code: InlineCode,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString {
        var inner = AttributedString(code.code)
        let range = fullRange(in: inner)
        let current = inner[range].inlinePresentationIntent ?? []
        inner[range].inlinePresentationIntent = current.union(.code).union(intents)
        inner[range].font = inlineCodeFont
        inner[range].backgroundColor = style.codeBackground
        if isStrikethrough {
            applyStrikethrough(to: &inner)
        }
        return wrapInlineMarkers(inner, prefix: "`", suffix: "`")
    }

    private func inlineLinkAttributedString(
        _ link: Markdown.Link,
        intents: InlinePresentationIntent,
        isStrikethrough: Bool
    ) -> AttributedString {
        var inner = AttributedString()
        for child in link.children {
            inner.append(inlineAttributedString(for: child, intents: intents, isStrikethrough: isStrikethrough))
        }
        if let destination = link.destination,
           let url = URL(string: destination) {
            inner[fullRange(in: inner)].link = url
            inner[fullRange(in: inner)].foregroundColor = .accentColor
            inner[fullRange(in: inner)].underlineStyle = .single
        }
        return inner
    }

    private func inlineImageAttributedString(_ image: Markdown.Image) -> AttributedString {
        let alt = unwrapOptionalString(image.plainText)
        let source = unwrapOptionalString(image.source)
        // Store image info for round-trip, display as placeholder for now
        // swiftlint:disable:next todo
        // TODO: Use AdaptiveImageGlyph when API is available
        var imageString = AttributedString("![\(alt)](\(source))")
        if let url = URL(string: source) {
            let range = fullRange(in: imageString)
            imageString[range].imageInfo = ImageInfo(url: url, altText: alt)
            imageString[range].foregroundColor = DesignTokens.Colors.textSecondary
        }
        return imageString
    }
}
