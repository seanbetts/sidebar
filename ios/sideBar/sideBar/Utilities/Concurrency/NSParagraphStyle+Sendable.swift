@preconcurrency import Foundation
#if canImport(UIKit)
@preconcurrency import UIKit
#elseif canImport(AppKit)
@preconcurrency import AppKit
#endif

extension NSParagraphStyle: @unchecked Sendable {}
