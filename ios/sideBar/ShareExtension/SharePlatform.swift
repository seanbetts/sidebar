import Foundation

#if canImport(UIKit)
import UIKit

typealias SharePlatformViewController = UIViewController
typealias SharePlatformView = UIView
typealias SharePlatformImage = UIImage

func shareApplyDefaultHostBackground(to view: SharePlatformView) {
    view.backgroundColor = .systemBackground
}
#elseif canImport(AppKit)
import AppKit

typealias SharePlatformViewController = NSViewController
typealias SharePlatformView = NSView
typealias SharePlatformImage = NSImage

func shareApplyDefaultHostBackground(to view: SharePlatformView) {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
}
#endif
