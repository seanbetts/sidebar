import Foundation
import ImageIO

enum ShareLoadingAssetVariant {
    case standard
    case hero
}

enum ShareGIFAnimationTiming {
    static let minimumFrameDuration: TimeInterval = 0.02
    static let fallbackFrameDuration: TimeInterval = 0.1
    static let frameStep: TimeInterval = 0.01

    static func normalizedDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration > 0 else {
            return fallbackFrameDuration
        }
        return max(duration, minimumFrameDuration)
    }

    static func repeatCount(for duration: TimeInterval) -> Int {
        let normalized = normalizedDuration(duration)
        return max(1, Int((normalized / frameStep).rounded()))
    }

    static func expandedDuration(for repeatedFrameCount: Int) -> TimeInterval {
        TimeInterval(repeatedFrameCount) * frameStep
    }
}

#if canImport(UIKit)
import UIKit

enum ShareLoadingAsset {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(
        for traitCollection: UITraitCollection,
        variant: ShareLoadingAssetVariant = .standard
    ) -> UIImage? {
        let darkMode = traitCollection.userInterfaceStyle == .dark
        let key = assetName(darkMode: darkMode, variant: variant)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        guard let decoded = decodeAnimatedImage(named: key) else {
            return nil
        }
        cache.setObject(decoded, forKey: key as NSString)
        return decoded
    }

    private static func decodeAnimatedImage(named name: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }

        var frames: [UIImage] = []

        for index in 0 ..< frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let frameImage = UIImage(cgImage: cgImage)
            let duration = frameDuration(for: source, index: index)
            let repeatCount = ShareGIFAnimationTiming.repeatCount(for: duration)
            for _ in 0 ..< repeatCount {
                frames.append(frameImage)
            }
        }

        guard !frames.isEmpty else { return nil }
        if frames.count == 1 {
            return frames[0]
        }

        let duration = ShareGIFAnimationTiming.expandedDuration(for: frames.count)
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(for source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? ShareGIFAnimationTiming.fallbackFrameDuration
        return ShareGIFAnimationTiming.normalizedDuration(value)
    }

    private static func assetName(darkMode: Bool, variant: ShareLoadingAssetVariant) -> String {
        switch (darkMode, variant) {
        case (true, .standard):
            return "loading-dark"
        case (false, .standard):
            return "loading-light"
        case (true, .hero):
            return "loading-dark-128"
        case (false, .hero):
            return "loading-light-128"
        }
    }
}
#elseif canImport(AppKit)
import AppKit

enum ShareLoadingAsset {
    private static var cache: [String: NSImage] = [:]

    static func image(for appearance: NSAppearance, variant: ShareLoadingAssetVariant = .standard) -> NSImage? {
        let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let key = assetName(darkMode: darkMode, variant: variant)
        if let cached = cache[key] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: key, withExtension: "gif"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[key] = image
        return image
    }

    private static func assetName(darkMode: Bool, variant: ShareLoadingAssetVariant) -> String {
        switch (darkMode, variant) {
        case (true, .standard):
            return "loading-dark"
        case (false, .standard):
            return "loading-light"
        case (true, .hero):
            return "loading-dark-128"
        case (false, .hero):
            return "loading-light-128"
        }
    }
}
#endif
