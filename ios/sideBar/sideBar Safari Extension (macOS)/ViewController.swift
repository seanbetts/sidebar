//
//  ViewController.swift
//  sideBar Safari Extension (macOS)
//
//  Created by Sean Betts on 01/02/2026.
//

import WebKit

#if canImport(AppKit)
import AppKit
typealias PlatformViewController = NSViewController
#else
import UIKit
typealias PlatformViewController = UIViewController
#endif

class ViewController: PlatformViewController, WKNavigationDelegate, WKScriptMessageHandler {
    @IBOutlet var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        webView.navigationDelegate = self
#if canImport(UIKit)
        webView.scrollView.isScrollEnabled = false
#endif
        webView.configuration.userContentController.add(self, name: "controller")

        webView.loadFileURL(
            Bundle.main.url(forResource: "Main", withExtension: "html")!,
            allowingReadAccessTo: Bundle.main.resourceURL!
        )
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}
