import Combine
import SwiftUI
import WebKit
import os
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - CodeMirrorEditorView

final class CodeMirrorEditorHandle: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    fileprivate var setMarkdownHandler: ((String) -> Void)?
    fileprivate var getMarkdownHandler: ((@escaping (String?) -> Void) -> Void)?
    fileprivate var setReadOnlyHandler: ((Bool) -> Void)?
    fileprivate var focusHandler: (() -> Void)?
    fileprivate var applyCommandHandler: ((String, Any?) -> Void)?
    fileprivate var setSelectionAtHandler: ((CGPoint) -> Void)?
    fileprivate var setSelectionAtDeferredHandler: ((CGPoint) -> Void)?

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

    func setSelectionAt(x xOffset: CGFloat, y yOffset: CGFloat) {
        setSelectionAtHandler?(CGPoint(x: xOffset, y: yOffset))
    }

    func setSelectionAtDeferred(x xOffset: CGFloat, y yOffset: CGFloat) {
        setSelectionAtDeferredHandler?(CGPoint(x: xOffset, y: yOffset))
    }
}

struct CodeMirrorEditorView: View {
    let markdown: String
    let isReadOnly: Bool
    let handle: CodeMirrorEditorHandle
    let onContentChanged: (String) -> Void
    let onEscape: (() -> Void)?
    let onRequestEdit: ((CGPoint) -> Void)?

    var body: some View {
        #if os(macOS)
        CodeMirrorEditorMac(
            markdown: markdown,
            isReadOnly: isReadOnly,
            handle: handle,
            onContentChanged: onContentChanged,
            onEscape: onEscape,
            onRequestEdit: onRequestEdit
        )
        #else
        CodeMirrorEditorIOS(
            markdown: markdown,
            isReadOnly: isReadOnly,
            handle: handle,
            onContentChanged: onContentChanged,
            onEscape: onEscape,
            onRequestEdit: onRequestEdit
        )
        #endif
    }
}

private enum CodeMirrorBridge {
    static let editorReady = "editorReady"
    static let contentChanged = "contentChanged"
    static let linkTapped = "linkTapped"
    static let jsError = "jsError"
    static let escapePressed = "escapePressed"
    static let requestEdit = "requestEdit"
}

private final class CodeMirrorCoordinator: NSObject, WKScriptMessageHandler {
    private let onContentChanged: (String) -> Void
    private let onEscape: (() -> Void)?
    private let onRequestEdit: ((CGPoint) -> Void)?
    private var webView: WKWebView?
    private var schemeHandler: CodeMirrorSchemeHandler?
    private var lastKnownMarkdown = ""
    private var pendingMarkdown: String?
    private var pendingReadOnly: Bool?
    private var pendingFocus = false
    private var isReady = false
    private var debounceWorkItem: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 0.3
    private let logger = Logger(subsystem: "sideBar", category: "CodeMirrorEditor")

    init(
        onContentChanged: @escaping (String) -> Void,
        onEscape: (() -> Void)?,
        onRequestEdit: ((CGPoint) -> Void)?
    ) {
        self.onContentChanged = onContentChanged
        self.onEscape = onEscape
        self.onRequestEdit = onRequestEdit
    }

    func attach(webView: WKWebView, handle: CodeMirrorEditorHandle, schemeHandler: CodeMirrorSchemeHandler) {
        self.webView = webView
        self.schemeHandler = schemeHandler
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
            self?.requestFocus()
        }
        handle.applyCommandHandler = { [weak self] command, payload in
            self?.applyCommand(command, payload: payload)
        }
        handle.setSelectionAtHandler = { [weak self] point in
            self?.setSelectionAt(point)
        }
        handle.setSelectionAtDeferredHandler = { [weak self] point in
            self?.setSelectionAtDeferred(point)
        }
    }

    func update(markdown: String, isReadOnly: Bool) {
        if isReady {
            if markdown != lastKnownMarkdown {
                setMarkdown(markdown)
            }
            setReadOnly(isReadOnly)
        } else {
            pendingMarkdown = markdown
            pendingReadOnly = isReadOnly
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case CodeMirrorBridge.editorReady:
            handleEditorReady()
        case CodeMirrorBridge.contentChanged:
            handleContentChanged(message)
        case CodeMirrorBridge.linkTapped:
            handleLinkTapped(message)
        case CodeMirrorBridge.jsError:
            handleJsError(message)
        case CodeMirrorBridge.escapePressed:
            handleEscapePressed()
        case CodeMirrorBridge.requestEdit:
            handleRequestEdit(message)
        default:
            break
        }
    }

    private func handleEditorReady() {
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
        if pendingFocus {
            pendingFocus = false
            evaluateJavaScript("window.editorAPI?.focus?.()")
        }
    }

    private func handleContentChanged(_ message: WKScriptMessage) {
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
    }

    private func handleLinkTapped(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let href = body["href"] as? String else {
            return
        }
        openExternalLink(href)
    }

    private func handleJsError(_ message: WKScriptMessage) {
        if let body = message.body as? [String: Any] {
            let messageText = body["message"] as? String ?? "Unknown error"
            let type = body["type"] as? String ?? "error"
            logger.error("CodeMirror JS error (\(type, privacy: .public)): \(messageText, privacy: .public)")
            logger.error("CodeMirror JS error payload: \(String(describing: body), privacy: .public)")
            if let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted]),
               let jsonString = String(data: data, encoding: .utf8) {
                logger.error("CodeMirror JS error payload JSON: \(jsonString, privacy: .public)")
            }
        } else {
            logger.error("CodeMirror JS error: \(String(describing: message.body), privacy: .public)")
        }
    }

    private func handleEscapePressed() {
        DispatchQueue.main.async { [weak self] in
            self?.onEscape?()
        }
    }

    private func handleRequestEdit(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let x = body["x"] as? CGFloat,
              let y = body["y"] as? CGFloat else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onRequestEdit?(CGPoint(x: x, y: y))
        }
    }

    private func setMarkdown(_ text: String) {
        lastKnownMarkdown = text
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

    private func setSelectionAt(_ point: CGPoint) {
        let payload = ["x": point.x, "y": point.y]
        let payloadValue = jsonEncoded(payload)
        evaluateJavaScript("window.editorAPI?.setSelectionAtCoords?.(\(payloadValue))")
    }

    private func setSelectionAtDeferred(_ point: CGPoint) {
        let payload = ["x": point.x, "y": point.y]
        let payloadValue = jsonEncoded(payload)
        evaluateJavaScript("window.editorAPI?.setSelectionAtCoordsDeferred?.(\(payloadValue))")
    }

    private func requestFocus() {
        guard isReady else {
            pendingFocus = true
            return
        }
        evaluateJavaScript("window.editorAPI?.focus?.()")
    }

    private func openExternalLink(_ href: String) {
        guard let url = URL(string: href) else {
            logger.error("CodeMirror link invalid: \(href, privacy: .public)")
            return
        }
        DispatchQueue.main.async {
            #if os(macOS)
            NSWorkspace.shared.open(url)
            #else
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            #endif
        }
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
        if let string = value as? String {
            return jsonEncodedScalar(string)
        }
        if let number = value as? NSNumber {
            return jsonEncodedScalar(number)
        }
        if let array = value as? [Any] {
            return jsonEncodedObject(array) ?? "null"
        }
        if let dict = value as? [String: Any] {
            return jsonEncodedObject(dict) ?? "null"
        }
        if value is NSNull {
            return "null"
        }
        return "null"
    }

    private func jsonEncodedScalar(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
              var string = String(data: data, encoding: .utf8) else {
            return "null"
        }
        if string.hasPrefix("[") && string.hasSuffix("]") {
            string.removeFirst()
            string.removeLast()
        }
        return string
    }

    private func jsonEncodedObject(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

extension CodeMirrorCoordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("CodeMirror webview didFinish navigation")
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
    let onEscape: (() -> Void)?
    let onRequestEdit: ((CGPoint) -> Void)?

    func makeCoordinator() -> CodeMirrorCoordinator {
        CodeMirrorCoordinator(
            onContentChanged: onContentChanged,
            onEscape: onEscape,
            onRequestEdit: onRequestEdit
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let schemeHandler = CodeMirrorSchemeHandler()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "codemirror")
        let errorScript = WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
              try {
                window.webkit?.messageHandlers?.jsError?.postMessage({
                  message: event.message || 'Unknown error',
                  source: event.filename || '',
                  line: event.lineno || 0,
                  column: event.colno || 0
                });
              } catch (e) {
                window.webkit?.messageHandlers?.jsError?.postMessage({ message: 'Error handler failed' });
              }
            });
            window.addEventListener('unhandledrejection', function(event) {
              try {
                window.webkit?.messageHandlers?.jsError?.postMessage({
                  message: event.reason && event.reason.message ? event.reason.message : String(event.reason || 'Unhandled rejection')
                });
              } catch (e) {
                window.webkit?.messageHandlers?.jsError?.postMessage({ message: 'Rejection handler failed' });
              }
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(errorScript)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.editorReady)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.contentChanged)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.linkTapped)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.jsError)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.escapePressed)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.requestEdit)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.attach(webView: webView, handle: handle, schemeHandler: schemeHandler)
        loadEditor(in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown, isReadOnly: isReadOnly)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: CodeMirrorCoordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.editorReady)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.contentChanged)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.linkTapped)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.jsError)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.escapePressed)
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.requestEdit)
    }
}
#else
private struct CodeMirrorEditorIOS: UIViewRepresentable {
    let markdown: String
    let isReadOnly: Bool
    let handle: CodeMirrorEditorHandle
    let onContentChanged: (String) -> Void
    let onEscape: (() -> Void)?
    let onRequestEdit: ((CGPoint) -> Void)?

    func makeCoordinator() -> CodeMirrorCoordinator {
        CodeMirrorCoordinator(
            onContentChanged: onContentChanged,
            onEscape: onEscape,
            onRequestEdit: onRequestEdit
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let schemeHandler = CodeMirrorSchemeHandler()
        configuration.setURLSchemeHandler(schemeHandler, forURLScheme: "codemirror")
        let errorScript = WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
              try {
                window.webkit?.messageHandlers?.jsError?.postMessage({
                  message: event.message || 'Unknown error',
                  source: event.filename || '',
                  line: event.lineno || 0,
                  column: event.colno || 0
                });
              } catch (e) {
                window.webkit?.messageHandlers?.jsError?.postMessage({ message: 'Error handler failed' });
              }
            });
            window.addEventListener('unhandledrejection', function(event) {
              try {
                window.webkit?.messageHandlers?.jsError?.postMessage({
                  message: event.reason && event.reason.message ? event.reason.message : String(event.reason || 'Unhandled rejection')
                });
              } catch (e) {
                window.webkit?.messageHandlers?.jsError?.postMessage({ message: 'Rejection handler failed' });
              }
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(errorScript)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.editorReady)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.contentChanged)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.linkTapped)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.jsError)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.escapePressed)
        configuration.userContentController.add(context.coordinator, name: CodeMirrorBridge.requestEdit)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        context.coordinator.attach(webView: webView, handle: handle, schemeHandler: schemeHandler)
        loadEditor(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.update(markdown: markdown, isReadOnly: isReadOnly)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: CodeMirrorCoordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.editorReady)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.contentChanged)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.linkTapped)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.jsError)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.escapePressed)
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: CodeMirrorBridge.requestEdit)
    }
}
#endif

private func loadEditor(in webView: WKWebView) {
    guard let url = URL(string: "codemirror://editor.html") else {
        let logger = Logger(subsystem: "sideBar", category: "CodeMirrorEditor")
        logger.error("CodeMirror editor URL invalid")
        return
    }
    webView.load(URLRequest(url: url))
}

private final class CodeMirrorSchemeHandler: NSObject, WKURLSchemeHandler {
    private let logger = Logger(subsystem: "sideBar", category: "CodeMirrorSchemeHandler")

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path.isEmpty ? "editor.html" : url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let bundlePath = Bundle.main.path(forResource: path, ofType: nil, inDirectory: "CodeMirror")

        guard let bundlePath else {
            logger.error("CodeMirror resource missing: \(path, privacy: .public)")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
            let mimeType = mimeTypeForPath(path)
            let response = URLResponse(
                url: url,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: mimeType.hasPrefix("text/") ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            logger.error("CodeMirror resource read failed: \(error.localizedDescription, privacy: .public)")
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    }

    private func mimeTypeForPath(_ path: String) -> String {
        if path.hasSuffix(".html") {
            return "text/html"
        }
        if path.hasSuffix(".css") {
            return "text/css"
        }
        if path.hasSuffix(".js") {
            return "application/javascript"
        }
        return "application/octet-stream"
    }
}
