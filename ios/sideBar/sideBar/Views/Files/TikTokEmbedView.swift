import SwiftUI
import WebKit
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(macOS)
public struct TikTokEmbedView: NSViewRepresentable {
    let embed: MarkdownRendering.MarkdownTikTokEmbed
    let onLoadStateChange: (Bool) -> Void

    public init(
        embed: MarkdownRendering.MarkdownTikTokEmbed,
        onLoadStateChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.embed = embed
        self.onLoadStateChange = onLoadStateChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(embed: embed, onLoadStateChange: onLoadStateChange)
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = makeConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.notifyLoadState(false)
        webView.loadHTMLString(
            makeHTML(embed: embed),
            baseURL: Self.embedBaseURL
        )
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        if context.coordinator.lastSourceURL != embed.sourceURL {
            context.coordinator.lastSourceURL = embed.sourceURL
            context.coordinator.notifyLoadState(false)
            nsView.loadHTMLString(makeHTML(embed: embed), baseURL: Self.embedBaseURL)
        }
    }

    public static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.notifyLoadState(false)
        YouTubePlayerWebViewLifecycle.prepareForTeardown(nsView)
    }
}
#else
public struct TikTokEmbedView: UIViewRepresentable {
    let embed: MarkdownRendering.MarkdownTikTokEmbed
    let onLoadStateChange: (Bool) -> Void

    public init(
        embed: MarkdownRendering.MarkdownTikTokEmbed,
        onLoadStateChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.embed = embed
        self.onLoadStateChange = onLoadStateChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(embed: embed, onLoadStateChange: onLoadStateChange)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = makeConfiguration(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.notifyLoadState(false)
        webView.loadHTMLString(
            makeHTML(embed: embed),
            baseURL: Self.embedBaseURL
        )
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        if context.coordinator.lastSourceURL != embed.sourceURL {
            context.coordinator.lastSourceURL = embed.sourceURL
            context.coordinator.notifyLoadState(false)
            uiView.loadHTMLString(makeHTML(embed: embed), baseURL: Self.embedBaseURL)
        }
    }

    public static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.notifyLoadState(false)
        YouTubePlayerWebViewLifecycle.prepareForTeardown(uiView)
    }
}
#endif

extension TikTokEmbedView {
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var lastSourceURL: String
        var onLoadStateChange: (Bool) -> Void
        private let logger = Logger(subsystem: "sideBar", category: "TikTokEmbed")

        init(
            embed: MarkdownRendering.MarkdownTikTokEmbed,
            onLoadStateChange: @escaping (Bool) -> Void
        ) {
            self.lastSourceURL = embed.sourceURL
            self.onLoadStateChange = onLoadStateChange
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playerState",
               let state = message.body as? String,
               state == "embedLoaded" {
                notifyLoadState(true)
                return
            }
            logger.info("TikTok webview console: \(String(describing: message.body), privacy: .public)")
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("TikTok webview navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let externalURL = externalURL(for: navigationAction) {
                openExternally(externalURL)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                openExternally(url)
            }
            return nil
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("TikTok webview provisional navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("TikTok webview content process terminated")
            notifyLoadState(false)
        }

        func notifyLoadState(_ isLoaded: Bool) {
            Task { @MainActor in
                onLoadStateChange(isLoaded)
            }
        }

        private func externalURL(for navigationAction: WKNavigationAction) -> URL? {
            let isLinkActivation = navigationAction.navigationType == .linkActivated
            let isNewWindow = navigationAction.targetFrame == nil
            guard isLinkActivation || isNewWindow else { return nil }
            guard let url = navigationAction.request.url,
                  let host = url.host?.lowercased(),
                  host == "www.tiktok.com" || host == "tiktok.com" else {
                return nil
            }
            return url
        }

        private func openExternally(_ url: URL) {
            Task { @MainActor in
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #else
                UIApplication.shared.open(url)
                #endif
            }
        }
    }

    fileprivate static let embedBaseURL = URL(string: "https://www.tiktok.com")

    fileprivate func makeConfiguration(coordinator: Coordinator) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        #if os(iOS)
        configuration.allowsInlineMediaPlayback = true
        #endif
        if #available(iOS 10.0, macOS 10.12, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 15.0, macOS 14.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        controller.add(coordinator, name: "consoleLog")
        controller.add(coordinator, name: "playerState")
        configuration.userContentController = controller
        return configuration
    }

    fileprivate func makeHTML(embed: MarkdownRendering.MarkdownTikTokEmbed) -> String {
        let escapedSourceURL = htmlEscaped(embed.sourceURL)
        let escapedVideoID = htmlEscaped(embed.videoId)
        let escapedAuthorURL = htmlEscaped(embed.authorURL ?? embed.sourceURL)
        let authorLabel = embed.authorName.map(htmlEscaped) ?? "TikTok creator"
        let escapedTitle = htmlEscaped(embed.title)

        return """
        <!doctype html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0\">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; min-height: 100%; overflow: hidden; }
              body { display: flex; justify-content: center; align-items: stretch; }
              .tiktok-embed { margin: 0 !important; width: 100% !important; min-width: 0 !important; max-width: 100% !important; }
            </style>
            <script>
              (function() {
                var loaded = false;
                function post(name, value) {
                  try {
                    window.webkit.messageHandlers[name].postMessage(value);
                  } catch (e) {}
                }
                function notifyLoaded() {
                  if (loaded) { return; }
                  loaded = true;
                  post("playerState", "embedLoaded");
                }
                var observer = new MutationObserver(function() {
                  if (document.querySelector("iframe")) {
                    notifyLoaded();
                  }
                });
                window.addEventListener("load", function() {
                  observer.observe(document.body, { childList: true, subtree: true });
                  setTimeout(function() {
                    if (document.querySelector("iframe")) {
                      notifyLoaded();
                    }
                  }, 1500);
                });
                var originalLog = console.log;
                console.log = function() {
                  post("consoleLog", Array.from(arguments).join(" "));
                  if (originalLog) { originalLog.apply(console, arguments); }
                };
              })();
            </script>
          </head>
          <body>
            <blockquote
              class=\"tiktok-embed\"
              cite=\"\(escapedSourceURL)\"
              data-video-id=\"\(escapedVideoID)\"
              data-embed-from=\"oembed\"
              style=\"max-width: 605px; min-width: 325px;\">
              <section>
                <a target=\"_blank\" title=\"\(authorLabel)\" href=\"\(escapedAuthorURL)\">\(authorLabel)</a>
                <p>\(escapedTitle)</p>
              </section>
            </blockquote>
            <script async src=\"https://www.tiktok.com/embed.js\"></script>
          </body>
        </html>
        """
    }

    fileprivate func htmlEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
