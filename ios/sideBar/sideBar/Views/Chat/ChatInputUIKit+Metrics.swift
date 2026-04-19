#if os(iOS)
import SwiftUI
import UIKit

extension ChatInputUIKitView {
    private var resolvedTextSizeOption: AppTextSizeOption {
        AppTextSizeOption.resolved(from: appTextSizeRaw)
    }

    private var textInsetTop: CGFloat {
        AppFontStyle.scaledMetric(12, for: resolvedTextSizeOption)
    }

    private var textInsetBottom: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    private var textInsetLeading: CGFloat {
        AppFontStyle.scaledMetric(44, for: resolvedTextSizeOption)
    }

    private var textInsetTrailing: CGFloat {
        AppFontStyle.scaledMetric(48, for: resolvedTextSizeOption)
    }

    private var sideButtonSymbolSize: CGFloat {
        AppFontStyle.scaledMetric(DesignTokens.Icon.md, for: resolvedTextSizeOption)
    }

    private var sideButtonHorizontalInset: CGFloat {
        AppFontStyle.scaledMetric(10, for: resolvedTextSizeOption)
    }

    private var placeholderTopInset: CGFloat {
        AppFontStyle.scaledMetric(8, for: resolvedTextSizeOption)
    }

    private var usesSystemTextSizeOption: Bool {
        resolvedTextSizeOption == .system
    }

    private func textFont() -> UIFont {
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
