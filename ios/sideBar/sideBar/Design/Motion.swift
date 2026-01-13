import SwiftUI

enum Motion {
    static func quick(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: DesignTokens.Animation.quick)
    }

    static func standard(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: DesignTokens.Animation.standard)
    }
}
