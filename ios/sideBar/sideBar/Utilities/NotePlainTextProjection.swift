import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
enum NotePlainTextProjection {
    static func plainText(from content: AttributedString) -> String {
        String(content.characters)
    }
}
