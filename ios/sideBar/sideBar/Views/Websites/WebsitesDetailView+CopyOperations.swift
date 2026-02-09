import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension WebsitesDetailView {
    func copyWebsiteContent() {
        guard let content = viewModel.active?.content, !content.isEmpty else { return }
        let stripped = MarkdownRendering.stripFrontmatter(content)
        guard !stripped.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = stripped
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(stripped, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == stripped {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == stripped {
                pasteboard.string = ""
            }
            #endif
        }
    }

    func copyWebsiteURL() {
        guard let urlString = sourceURL?.absoluteString, !urlString.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = urlString
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == urlString {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == urlString {
                pasteboard.string = ""
            }
            #endif
        }
    }

    func copyWebsiteTitle() {
        guard let website = viewModel.active else { return }
        let title = website.title.isEmpty ? website.url : website.title
        guard !title.isEmpty else { return }
        #if os(iOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = title
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(title, forType: .string)
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            #if os(macOS)
            let pasteboard = NSPasteboard.general
            if pasteboard.string(forType: .string) == title {
                pasteboard.clearContents()
            }
            #else
            let pasteboard = UIPasteboard.general
            if pasteboard.string == title {
                pasteboard.string = ""
            }
            #endif
        }
    }
}
