import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
func serializeInline(_ attributed: AttributedSubstring) -> String {
    var output = ""

    for run in attributed.runs {
        if run.listMarker == true {
            continue
        }

        if let imageInfo = run.imageInfo {
            output += "![\(imageInfo.altText)](\(imageInfo.url.absoluteString))"
            continue
        }

        let text = String(attributed[run.range].characters)
        let intents = run.inlinePresentationIntent ?? []
        let isBold = intents.contains(.stronglyEmphasized)
        let isItalic = intents.contains(.emphasized)
        let isCode = intents.contains(.code)
        let isStrike = run.strikethroughStyle != nil
        let link = run.link

        var content = isCode ? wrappedInlineCode(text) : escapeInlineText(text)
        if isStrike {
            content = "~~\(content)~~"
        }
        if isItalic {
            content = "*\(content)*"
        }
        if isBold {
            content = "**\(content)**"
        }

        if let link {
            output += "[\(content)](\(escapedLinkDestination(link.absoluteString)))"
        } else {
            output += content
        }
    }

    return output
}

@available(iOS 26.0, macOS 26.0, *)
func filteredText(from attributed: AttributedSubstring) -> String {
    var result = ""
    for run in attributed.runs {
        if run.listMarker == true {
            continue
        }
        result += String(attributed[run.range].characters)
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
private func wrappedInlineCode(_ text: String) -> String {
    let fence = inlineCodeFence(for: text)
    return "\(fence)\(text)\(fence)"
}

@available(iOS 26.0, macOS 26.0, *)
private func inlineCodeFence(for text: String) -> String {
    var length = 1
    while text.contains(String(repeating: "`", count: length)) {
        length += 1
    }
    return String(repeating: "`", count: length)
}

@available(iOS 26.0, macOS 26.0, *)
private func escapeInlineText(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    for character in text {
        switch character {
        case "\\":
            result += "\\\\"
        case "*", "_", "`", "~", "[", "]":
            result += "\\\(character)"
        default:
            result.append(character)
        }
    }
    return result
}

@available(iOS 26.0, macOS 26.0, *)
private func escapedLinkDestination(_ destination: String) -> String {
    destination
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: ")", with: "\\)")
}
