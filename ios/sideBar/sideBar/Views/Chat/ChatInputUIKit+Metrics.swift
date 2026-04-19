#if os(iOS)
import SwiftUI
import UIKit

extension ChatInputUIKitView {
    var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    var textInsetTop: CGFloat {
        AppFontStyle.scaledMetric(12, for: resolvedTextSizeOption)
    }

    var textInsetBottom: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    var textInsetLeading: CGFloat {
        AppFontStyle.scaledMetric(44, for: resolvedTextSizeOption)
    }

    var textInsetTrailing: CGFloat {
        AppFontStyle.scaledMetric(48, for: resolvedTextSizeOption)
    }

    var sideButtonSymbolSize: CGFloat {
        AppFontStyle.scaledMetric(DesignTokens.Icon.md, for: resolvedTextSizeOption)
    }

    var sideButtonHorizontalInset: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    var placeholderTopInset: CGFloat {
        AppFontStyle.scaledMetric(8, for: resolvedTextSizeOption)
    }

    var usesSystemTextSizeOption: Bool {
        resolvedTextSizeOption == .system
    }

    func textFont() -> UIFont {
        let option = resolvedTextSizeOption
        switch option {
        case .system:
            return UIFont.preferredFont(forTextStyle: .body)
        case .small, .medium, .large:
            return UIFont.systemFont(ofSize: AppFontStyle.body.pointSize(for: option))
        }
    }

    func makePlaceholderLabel(
        font: UIFont,
        adjustsForContentSizeCategory: Bool
    ) -> UILabel {
        let label = UILabel()
        label.text = "Ask Anything..."
        label.font = font
        label.adjustsFontForContentSizeCategory = adjustsForContentSizeCategory
        label.textColor = UIColor.secondaryLabel
        label.numberOfLines = 1
        return label
    }

    func makeAccessoryButton(systemName: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(
                systemName: systemName,
                withConfiguration: UIImage.SymbolConfiguration(
                    pointSize: sideButtonSymbolSize,
                    weight: .semibold
                )
            ),
            for: .normal
        )
        button.clipsToBounds = true
        return button
    }
}
#endif
