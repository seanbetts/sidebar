import CoreGraphics

public enum LayoutMetrics {
    public static var appHeaderMinHeight: CGFloat {
        #if os(macOS)
        return 64
        #else
        return 56
        #endif
    }

    public static var contentHeaderMinHeight: CGFloat {
        #if os(macOS)
        return 58
        #else
        return 52
        #endif
    }

    public static var panelHeaderMinHeight: CGFloat {
        appHeaderMinHeight + contentHeaderMinHeight + 7
    }
}
