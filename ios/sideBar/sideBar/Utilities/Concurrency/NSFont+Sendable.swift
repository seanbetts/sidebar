@preconcurrency import Foundation
#if canImport(AppKit)
@preconcurrency import AppKit

extension NSFont: @unchecked @retroactive Sendable {}
#endif
