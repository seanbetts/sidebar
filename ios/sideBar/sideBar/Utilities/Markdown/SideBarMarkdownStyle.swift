import SwiftUI

struct SideBarMarkdownStyle: Equatable {
    let codeBackground: Color
    let codeBlockBackground: Color

    static let `default` = SideBarMarkdownStyle(
        codeBackground: DesignTokens.Colors.muted,
        codeBlockBackground: DesignTokens.Colors.muted
    )

    static let chat = SideBarMarkdownStyle(
        codeBackground: DesignTokens.Colors.background,
        codeBlockBackground: DesignTokens.Colors.background
    )
}
