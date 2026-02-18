import SwiftUI
import ImageIO

enum LoadingIndicatorSize {
    static let inline: CGFloat = 16
    static let control: CGFloat = 20
    static let panel: CGFloat = 24
    static let page: CGFloat = 32
    static let extensionPrimary: CGFloat = 44
    static let hero: CGFloat = 128
}

enum LoadingIndicatorVariant {
    case standard
    case hero
}

enum GIFAnimationTiming {
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

struct LoadingIndicatorView: View {
    let size: CGFloat?
    let variant: LoadingIndicatorVariant

    init(size: CGFloat? = LoadingIndicatorSize.panel, variant: LoadingIndicatorVariant = .standard) {
        self.size = size
        self.variant = variant
    }

    var body: some View {
        Group {
            if let size {
                PlatformLoadingIndicatorView(variant: variant)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                PlatformLoadingIndicatorView(variant: variant)
            }
        }
        .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
import UIKit

private final class FixedLayoutUIImageView: UIImageView {
    override var intrinsicContentSize: CGSize {
        .zero
    }
}

private struct PlatformLoadingIndicatorView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let variant: LoadingIndicatorVariant

    func makeUIView(context: Context) -> FixedLayoutUIImageView {
        let imageView = FixedLayoutUIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        return imageView
    }

    func updateUIView(_ imageView: FixedLayoutUIImageView, context: Context) {
        let image = LoadingGIFImageCache.image(darkMode: colorScheme == .dark, variant: variant)
        if let image {
            if imageView.image !== image {
                imageView.image = image
            }
        } else if imageView.image != nil {
            imageView.image = nil
        }
    }
}

private enum LoadingGIFImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(darkMode: Bool, variant: LoadingIndicatorVariant) -> UIImage? {
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

    private static func assetName(darkMode: Bool, variant: LoadingIndicatorVariant) -> String {
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
            let repeatCount = GIFAnimationTiming.repeatCount(for: duration)
            for _ in 0 ..< repeatCount {
                frames.append(frameImage)
            }
        }

        guard !frames.isEmpty else { return nil }
        if frames.count == 1 {
            return frames[0]
        }

        let duration = GIFAnimationTiming.expandedDuration(for: frames.count)
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private static func frameDuration(for source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }

        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let value = unclamped ?? clamped ?? GIFAnimationTiming.fallbackFrameDuration
        return GIFAnimationTiming.normalizedDuration(value)
    }
}
#elseif canImport(AppKit)
import AppKit

private final class FixedLayoutNSImageView: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

private struct PlatformLoadingIndicatorView: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let variant: LoadingIndicatorVariant

    func makeNSView(context: Context) -> FixedLayoutNSImageView {
        let imageView = FixedLayoutNSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.animates = true
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        return imageView
    }

    func updateNSView(_ imageView: FixedLayoutNSImageView, context: Context) {
        let image = LoadingGIFImageCache.image(darkMode: colorScheme == .dark, variant: variant)
        if let image {
            if imageView.image !== image {
                imageView.image = image
            }
        } else if imageView.image != nil {
            imageView.image = nil
        }
    }
}

private enum LoadingGIFImageCache {
    private static var cache: [String: NSImage] = [:]

    static func image(darkMode: Bool, variant: LoadingIndicatorVariant) -> NSImage? {
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

    private static func assetName(darkMode: Bool, variant: LoadingIndicatorVariant) -> String {
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
