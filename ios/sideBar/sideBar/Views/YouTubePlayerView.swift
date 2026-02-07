import SwiftUI
import WebKit
import os

#if os(macOS)
// MARK: - YouTubePlayerView

public struct YouTubePlayerView: NSViewRepresentable {
    let url: URL
    let onLoadStateChange: (Bool) -> Void

    public init(url: URL, onLoadStateChange: @escaping (Bool) -> Void = { _ in }) {
        self.url = url
        self.onLoadStateChange = onLoadStateChange
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if #available(macOS 10.12, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = makeUserContentController(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.notifyLoadState(false)
        webView.loadHTMLString(makeHTML(url: url), baseURL: YouTubePlayerView.embedBaseURL)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            context.coordinator.notifyLoadState(false)
            nsView.loadHTMLString(makeHTML(url: url), baseURL: YouTubePlayerView.embedBaseURL)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onLoadStateChange: onLoadStateChange)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var lastURL: URL?
        var onLoadStateChange: (Bool) -> Void
        private let logger = Logger(subsystem: "sideBar", category: "YouTubePlayer")

        init(url: URL, onLoadStateChange: @escaping (Bool) -> Void) {
            self.lastURL = url
            self.onLoadStateChange = onLoadStateChange
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playerState",
               let state = message.body as? String,
               state == "iframeLoaded" {
                notifyLoadState(true)
                return
            }
            logger.info("YouTube webview console: \(String(describing: message.body), privacy: .public)")
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("YouTube webview navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("YouTube webview provisional navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("YouTube webview content process terminated")
            notifyLoadState(false)
        }

        func notifyLoadState(_ isLoaded: Bool) {
            Task { @MainActor in
                onLoadStateChange(isLoaded)
            }
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
            <script>
              (function() {
                var originalLog = console.log;
                var originalWarn = console.warn;
                var originalError = console.error;
                function post(type, args) {
                  try {
                    window.webkit.messageHandlers.consoleLog.postMessage(type + ": " + args.join(" "));
                  } catch (e) {
                    if (originalError) {
                      originalError.call(console, "consoleLog bridge failed", e);
                    }
                  }
                }
                console.log = function() {
                  post("log", Array.from(arguments));
                  if (originalLog) { originalLog.apply(console, arguments); }
                };
                console.warn = function() {
                  post("warn", Array.from(arguments));
                  if (originalWarn) { originalWarn.apply(console, arguments); }
                };
                console.error = function() {
                  post("error", Array.from(arguments));
                  if (originalError) { originalError.apply(console, arguments); }
                };
                window.addEventListener("error", function(event) {
                  post("window.error", [event.message || "unknown"]);
                });
                window.sideBarYouTubeIframeLoaded = function() {
                  try {
                    window.webkit.messageHandlers.playerState.postMessage("iframeLoaded");
                  } catch (e) {
                    post("warn", ["playerState bridge failed"]);
                  }
                };
              })();
            </script>
          </head>
          <body>
            <iframe
              src=\"\(escaped)\"
              allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\"
              allowfullscreen
              onload="window.sideBarYouTubeIframeLoaded && window.sideBarYouTubeIframeLoaded()"
            ></iframe>
          </body>
        </html>
        """
    }

    private func makeUserContentController(coordinator: Coordinator) -> WKUserContentController {
        let controller = WKUserContentController()
        controller.add(coordinator, name: "consoleLog")
        controller.add(coordinator, name: "playerState")
        return controller
    }

    private static let embedBaseURL = URL(string: "https://www.youtube-nocookie.com")
}
#else
public struct YouTubePlayerView: UIViewRepresentable {
    let url: URL
    let onLoadStateChange: (Bool) -> Void

    public init(url: URL, onLoadStateChange: @escaping (Bool) -> Void = { _ in }) {
        self.url = url
        self.onLoadStateChange = onLoadStateChange
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = []
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController = makeUserContentController(coordinator: context.coordinator)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        context.coordinator.onLoadStateChange = onLoadStateChange
        context.coordinator.notifyLoadState(false)
        webView.loadHTMLString(makeHTML(url: url), baseURL: YouTubePlayerView.embedBaseURL)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onLoadStateChange = onLoadStateChange
        if context.coordinator.lastURL != url {
            context.coordinator.lastURL = url
            context.coordinator.notifyLoadState(false)
            uiView.loadHTMLString(makeHTML(url: url), baseURL: YouTubePlayerView.embedBaseURL)
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onLoadStateChange: onLoadStateChange)
    }

    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var lastURL: URL?
        var onLoadStateChange: (Bool) -> Void
        private let logger = Logger(subsystem: "sideBar", category: "YouTubePlayer")

        init(url: URL, onLoadStateChange: @escaping (Bool) -> Void) {
            self.lastURL = url
            self.onLoadStateChange = onLoadStateChange
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "playerState",
               let state = message.body as? String,
               state == "iframeLoaded" {
                notifyLoadState(true)
                return
            }
            logger.info("YouTube webview console: \(String(describing: message.body), privacy: .public)")
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("YouTube webview navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("YouTube webview provisional navigation failed: \(error.localizedDescription, privacy: .public)")
            notifyLoadState(false)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        }

        public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            logger.error("YouTube webview content process terminated")
            notifyLoadState(false)
        }

        func notifyLoadState(_ isLoaded: Bool) {
            Task { @MainActor in
                onLoadStateChange(isLoaded)
            }
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
            <script>
              (function() {
                function post(type, args) {
                  try {
                    window.webkit.messageHandlers.consoleLog.postMessage(type + ": " + args.join(" "));
                  } catch (e) {}
                }
                var originalLog = console.log;
                var originalWarn = console.warn;
                var originalError = console.error;
                console.log = function() {
                  post("log", Array.from(arguments));
                  if (originalLog) { originalLog.apply(console, arguments); }
                };
                console.warn = function() {
                  post("warn", Array.from(arguments));
                  if (originalWarn) { originalWarn.apply(console, arguments); }
                };
                console.error = function() {
                  post("error", Array.from(arguments));
                  if (originalError) { originalError.apply(console, arguments); }
                };
                window.addEventListener("error", function(event) {
                  post("window.error", [event.message || "unknown"]);
                });
                window.sideBarYouTubeIframeLoaded = function() {
                  try {
                    window.webkit.messageHandlers.playerState.postMessage("iframeLoaded");
                  } catch (e) {
                    post("warn", ["playerState bridge failed"]);
                  }
                };
              })();
            </script>
          </head>
          <body>
            <iframe
              src=\"\(escaped)\"
              allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\"
              allowfullscreen
              onload="window.sideBarYouTubeIframeLoaded && window.sideBarYouTubeIframeLoaded()"
            ></iframe>
          </body>
        </html>
        """
    }

    private func makeUserContentController(coordinator: Coordinator) -> WKUserContentController {
        let controller = WKUserContentController()
        controller.add(coordinator, name: "consoleLog")
        controller.add(coordinator, name: "playerState")
        return controller
    }

    private static let embedBaseURL = URL(string: "https://www.youtube-nocookie.com")
}
#endif
