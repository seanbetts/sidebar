import Combine
import SwiftUI
import WebKit
import os

final class CodeMirrorEditorHandle: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    fileprivate var setMarkdownHandler: ((String) -> Void)?
    fileprivate var getMarkdownHandler: ((@escaping (String?) -> Void) -> Void)?
    fileprivate var setReadOnlyHandler: ((Bool) -> Void)?
    fileprivate var focusHandler: (() -> Void)?
    fileprivate var applyCommandHandler: ((String, Any?) -> Void)?

    func setMarkdown(_ text: String) {
        setMarkdownHandler?(text)
    }

    func getMarkdown(completion: @escaping (String?) -> Void) {
        getMarkdownHandler?(completion)
    }

    func setReadOnly(_ isReadOnly: Bool) {
        setReadOnlyHandler?(isReadOnly)
    }

    func focus() {
        focusHandler?()
    }

    func applyCommand(_ command: String, payload: Any? = nil) {
        applyCommandHandler?(command, payload)
    }
}

struct CodeMirrorEditorView: View {
    let markdown: String
    let isReadOnly: Bool
    let handle: CodeMirrorEditorHandle
    let onContentChanged: (String) -> Void

    var body: some View {
        #if os(macOS)
        CodeMirrorEditorMac(
            markdown: markdown,
            isReadOnly: isReadOnly,
            handle: handle,
            onContentChanged: onContentChanged
        )
        #else
        CodeMirrorEditorIOS(
            markdown: markdown,
            isReadOnly: isReadOnly,
            handle: handle,
            onContentChanged: onContentChanged
        )
        #endif
    }
}

private enum CodeMirrorBridge {
    static let editorReady = "editorReady"
    static let contentChanged = "contentChanged"
}

private final class CodeMirrorCoordinator: NSObject, WKScriptMessageHandler {
    private let onContentChanged: (String) -> Void
    private var webView: WKWebView?
    private var lastKnownMarkdown = ""
    private var pendingMarkdown: String?
    private var pendingReadOnly: Bool?
    private var isReady = false
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3
    private let logger = Logger(subsystem: "sideBar", category: "CodeMirrorEditor")

    init(onContentChanged: @escaping (String) -> Void) {
        self.onContentChanged = onContentChanged
    }

    func attach(webView: WKWebView, handle: CodeMirrorEditorHandle) {
        self.webView = webView
        webView.navigationDelegate = self
        handle.setMarkdownHandler = { [weak self] text in
            self?.setMarkdown(text)
        }
        handle.getMarkdownHandler = { [weak self] completion in
            self?.getMarkdown(completion: completion)
        }
        handle.setReadOnlyHandler = { [weak self] isReadOnly in
            self?.setReadOnly(isReadOnly)
        }
        handle.focusHandler = { [weak self] in
            self?.evaluateJavaScript("window.editorAPI?.focus?.()")
        }
        handle.applyCommandHandler = { [weak self] command, payload in
            self?.applyCommand(command, payload: payload)
        }
    }

    func update(markdown: String, isReadOnly: Bool) {
        logger.info("CodeMirror update markdown length: \(markdown.count)")
        if isReady {
            if markdown != lastKnownMarkdown {
                logger.info("CodeMirror send markdown length: \(markdown.count)")
                setMarkdown(markdown)
            }
            setReadOnly(isReadOnly)
        } else {
            logger.info("CodeMirror pending markdown length: \(markdown.count)")
            pendingMarkdown = markdown
            pendingReadOnly = isReadOnly
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case CodeMirrorBridge.editorReady:
            isReady = true
            logger.info("CodeMirror editorReady received")
            if let pendingMarkdown {
                setMarkdown(pendingMarkdown)
                self.pendingMarkdown = nil
            }
            if let pendingReadOnly {
                setReadOnly(pendingReadOnly)
                self.pendingReadOnly = nil
            }
        case CodeMirrorBridge.contentChanged:
            guard let body = message.body as? [String: Any],
                  let text = body["text"] as? String else {
                return
            }
            lastKnownMarkdown = text
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.onContentChanged(text)
            }
            debounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        default:
            break
        }
    }

    private func setMarkdown(_ text: String) {
        lastKnownMarkdown = text
        logger.info("CodeMirror setMarkdown invoked length: \(text.count)")
        evaluateJavaScript("window.editorAPI?.setMarkdown(\(jsonEncoded(text)))")
    }

    private func getMarkdown(completion: @escaping (String?) -> Void) {
        evaluateJavaScript("window.editorAPI?.getMarkdown()") { result in
            switch result {
            case .success(let value):
                completion(value as? String)
            case .failure:
                completion(nil)
            }
        }
    }

    private func setReadOnly(_ isReadOnly: Bool) {
        evaluateJavaScript("window.editorAPI?.setReadOnly(\(isReadOnly))")
    }

    private func applyCommand(_ command: String, payload: Any?) {
        let payloadValue = payload.map { jsonEncoded($0) } ?? "null"
        evaluateJavaScript("window.editorAPI?.applyCommand(\(jsonEncoded(command)), \(payloadValue))")
    }

    private func evaluateJavaScript(_ script: String, completion: ((Result<Any, Error>) -> Void)? = nil) {
        webView?.evaluateJavaScript(script) { value, error in
            if let error {
                self.logger.error("JS eval failed: \(String(describing: error), privacy: .public)")
                completion?(.failure(error))
                return
            }
            completion?(.success(value as Any))
        }
    }

    private func jsonEncoded(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return string
    }
}

extension CodeMirrorCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("CodeMirror webview didFinish navigation")
        evaluateJavaScript("window.editorAPI != null") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                self.logger.info("CodeMirror editorAPI present: \(String(describing: value), privacy: .public)")
            case .failure(let error):
                self.logger.error("CodeMirror editorAPI check failed: \(String(describing: error), privacy: .public)")
            }
        }
        evaluateJavaScript("document.readyState") { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                self.logger.info("CodeMirror document.readyState: \(String(describing: value), privacy: .public)")
            case .failure(let error):
                self.logger.error("CodeMirror readyState check failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("CodeMirror webview navigation failed: \(String(describing: error), privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("CodeMirror webview provisional navigation failed: \(String(describing: error), privacy: .public)")
    }
}

#if os(macOS)
private struct CodeMirrorEditorMac: NSViewRepresentable {
    let markdown: String
    let isReadOnly: Bool
    let handle: CodeMirrorEditorHandle
    let onContentChanged: (String) -> Void

    func makeCoordinator() -> CodeMirrorCoordinator {
        CodeMirrorCoordinator(onContentChanged: onContentChanged)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.preferences.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.editorReady)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.contentChanged)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView: webView, handle: handle)
        loadEditor(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown, isReadOnly: isReadOnly)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: CodeMirrorCoordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.editorReady)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.contentChanged)
    }
}
#else
private struct CodeMirrorEditorIOS: UIViewRepresentable {
    let markdown: String
    let isReadOnly: Bool
    let handle: CodeMirrorEditorHandle
    let onContentChanged: (String) -> Void

    func makeCoordinator() -> CodeMirrorCoordinator {
        CodeMirrorCoordinator(onContentChanged: onContentChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.preferences.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.editorReady)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.contentChanged)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.attach(webView: webView, handle: handle)
        loadEditor(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown, isReadOnly: isReadOnly)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: CodeMirrorCoordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.editorReady)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.contentChanged)
    }
}
#endif

private func loadEditor(in webView: WKWebView) {
    guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html", subdirectory: "CodeMirror") else {
        let logger = Logger(subsystem: "sideBar", category: "CodeMirrorEditor")
        logger.error("CodeMirror editor.html missing from bundle")
        return
    }
    webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
}
