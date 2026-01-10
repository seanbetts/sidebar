import SwiftUI
import WebKit

#if os(macOS)
public struct YouTubePlayerView: NSViewRepresentable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(macOS 10.12, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(makeHTML(url: url), baseURL: nil)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            nsView.loadHTMLString(makeHTML(url: url), baseURL: nil)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    public final class Coordinator {
        var lastURL: URL?

        init(url: URL) {
            self.lastURL = url
        }
    }

    private func makeHTML(url: URL) -> String {
        let escaped = url.absoluteString
        return """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"initial-scale=1.0, maximum-scale=1.0\">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; height: 100%; }
              iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
            </style>
          </head>
          <body>
            <iframe src=\"\(escaped)\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\" allowfullscreen></iframe>
          </body>
        </html>
        """
    }
}
#else
public struct YouTubePlayerView: UIViewRepresentable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        webView.loadHTMLString(makeHTML(url: url), baseURL: nil)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            uiView.loadHTMLString(makeHTML(url: url), baseURL: nil)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    public final class Coordinator {
        var lastURL: URL?

        init(url: URL) {
            self.lastURL = url
        }
    }

    private func makeHTML(url: URL) -> String {
        let escaped = url.absoluteString
        return """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"initial-scale=1.0, maximum-scale=1.0\">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; height: 100%; }
              iframe { position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
            </style>
          </head>
          <body>
            <iframe src=\"\(escaped)\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\" allowfullscreen></iframe>
          </body>
        </html>
        """
    }
}
#endif
