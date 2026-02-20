import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
func serializeInline(_ attributed: AttributedSubstring) -> String {
    let lineText = filteredText(from: attributed)
    let hasInlineMarkers = lineHasInlineMarkers(lineText)
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

        var prefix = ""
        var suffix = ""

        if isCode {
            prefix += "`"
            suffix = "`" + suffix
        }
        if isStrike {
            prefix += "~~"
            suffix = "~~" + suffix
        }
        if isItalic {
            prefix += "*"
            suffix = "*" + suffix
        }
        if isBold {
            prefix += "**"
            suffix = "**" + suffix
        }

        if let link {
            output += "[\(text)](\(link.absoluteString))"
        } else if hasInlineMarkers {
            output += text
        } else {
            output += "\(prefix)\(text)\(suffix)"
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
private func lineHasInlineMarkers(_ lineText: String) -> Bool {
    let patterns = [
        #"\*\*[^*]+?\*\*"#,
        #"__[^_]+?__"#,
        #"~~[^~]+?~~"#,
        #"`[^`]+?`"#,
        #"\*[^*]+?\*"#,
        #"_[^_]+?_"#
    ]

    for pattern in patterns where lineText.range(of: pattern, options: .regularExpression) != nil {
        return true
    }

    return false
}
