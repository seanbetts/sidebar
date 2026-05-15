import SwiftUI
import sideBarShared

#if canImport(UIKit)
import UIKit
public typealias PlatformTextContentType = UITextContentType
#elseif canImport(AppKit)
import AppKit
public typealias PlatformTextContentType = NSTextContentType
#else
public typealias PlatformTextContentType = String
#endif

enum FormFieldLayoutMetrics {
    static let settingsIOSMinHeight: CGFloat = 28
    static let settingsMacLabelWidth: CGFloat = 160
}

struct FormField<Content: View, Trailing: View>: View {
    private enum Layout {
        case settings(label: String)
        case auth(leadingIcon: AppIcon?)
    }

    private let layout: Layout
    private let content: Content
    private let trailing: Trailing

    init(_ label: String, @ViewBuilder content: () -> Content) where Trailing == EmptyView {
        layout = .settings(label: label)
        self.content = content()
        trailing = EmptyView()
    }

    init(
        leadingIcon: AppIcon? = nil,
        @ViewBuilder content: () -> Content
    ) where Trailing == EmptyView {
        layout = .auth(leadingIcon: leadingIcon)
        self.content = content()
        trailing = EmptyView()
    }

    init(
        leadingIcon: AppIcon? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        layout = .auth(leadingIcon: leadingIcon)
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        switch layout {
        case let .settings(label):
            settingsBody(label: label)
        case let .auth(leadingIcon):
            authBody(leadingIcon: leadingIcon)
        }
    }

    @ViewBuilder
    private func settingsBody(label: String) -> some View {
        #if os(macOS)
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Text(label)
                .appFont(.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(width: FormFieldLayoutMetrics.settingsMacLabelWidth, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        #else
        LabeledContent {
            content
                .frame(
                    maxWidth: .infinity,
                    minHeight: FormFieldLayoutMetrics.settingsIOSMinHeight,
                    alignment: .trailing
                )
        } label: {
            Text(label)
                .appFont(.body)
        }
        #endif
    }

    private func authBody(leadingIcon: AppIcon?) -> some View {
        HStack(spacing: LoginFieldChromeMetrics.rowSpacing) {
            if let leadingIcon {
                Image(appIcon: leadingIcon)
                    .foregroundStyle(.secondary)
                    .font(.system(size: LoginFieldChromeMetrics.trailingSymbolPointSize))
                    .frame(width: LoginFieldChromeMetrics.leadingIconWidth)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: LoginFieldChromeMetrics.trailingControlSpacing) {
                trailing
            }
        }
        .appFont(.subheading)
        .padding(.vertical, LoginFieldChromeMetrics.fieldVerticalPadding)
        .padding(.horizontal, LoginFieldChromeMetrics.fieldHorizontalPadding)
        .sidebarTextEntrySurface()
    }
}

public struct FormFieldSecureInput<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    var textContentType: PlatformTextContentType?
    var submitLabel: SubmitLabel
    var onSubmit: (() -> Void)?

    @State private var isSecure = true

    public init(
        title: String,
        text: Binding<String>,
        focus: FocusState<Field?>.Binding,
        field: Field,
        textContentType: PlatformTextContentType? = nil,
        submitLabel: SubmitLabel = .return,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        _text = text
        self.focus = focus
        self.field = field
        self.textContentType = textContentType
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: LoginFieldChromeMetrics.trailingControlSpacing) {
            Group {
                if isSecure {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textContentType(textContentType)
            .autocorrectionDisabled()
        #if canImport(UIKit)
            .textInputAutocapitalization(.never)
        #endif
            .textFieldStyle(.plain)
            .focused(focus, equals: field)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }

            Button {
                let wasFocused = focus.wrappedValue == field
                isSecure.toggle()
                if wasFocused {
                    DispatchQueue.main.async {
                        focus.wrappedValue = field
                    }
                }
            } label: {
                Image(appIcon: isSecure ? AppIcon.Auth.passwordHidden : AppIcon.Auth.passwordVisible)
                    .foregroundStyle(.secondary)
                    .font(.system(size: LoginFieldChromeMetrics.trailingSymbolPointSize))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSecure ? "Show password" : "Hide password")
        }
    }
}

struct SidebarSelectionMenu<Option: Hashable>: View {
    @Binding private var selection: Option
    private let options: [Option]
    private let accessibilityLabel: String
    private let title: (Option) -> String
    private let isPlaceholder: (Option) -> Bool
    private let maxWidth: CGFloat?

    init(
        selection: Binding<Option>,
        options: [Option],
        accessibilityLabel: String,
        maxWidth: CGFloat? = 320,
        title: @escaping (Option) -> String,
        isPlaceholder: @escaping (Option) -> Bool = { _ in false }
    ) {
        _selection = selection
        self.options = options
        self.accessibilityLabel = accessibilityLabel
        self.maxWidth = maxWidth
        self.title = title
        self.isPlaceholder = isPlaceholder
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(title(option)) {
                    selection = option
                }
            }
        } label: {
            SidebarSelectionTriggerLabel(
                title: title(selection),
                isPlaceholder: isPlaceholder(selection)
            )
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SidebarSelectionTriggerLabel: View {
    let title: String
    var isPlaceholder = false

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Spacer(minLength: DesignTokens.Spacing.xs)
            Text(title)
                .appFont(.subheading)
                .foregroundStyle(
                    isPlaceholder
                        ? DesignTokens.Colors.textSecondary
                        : DesignTokens.Colors.textPrimary
                )
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .appFont(.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .sidebarTextEntryControl()
    }
}

private struct SidebarTextEntrySurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(DesignTokens.Colors.input)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .stroke(DesignTokens.Colors.border.opacity(0.65), lineWidth: 1)
            )
    }
}

private struct SidebarTextEntryFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .sidebarTextEntrySurface()
    }
}

private struct SidebarTextEntryControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .sidebarTextEntrySurface()
    }
}

extension View {
    func sidebarTextEntrySurface() -> some View {
        modifier(SidebarTextEntrySurfaceModifier())
    }

    func sidebarTextEntryField() -> some View {
        modifier(SidebarTextEntryFieldModifier())
    }

    func sidebarTextEntryControl() -> some View {
        modifier(SidebarTextEntryControlModifier())
    }
}
