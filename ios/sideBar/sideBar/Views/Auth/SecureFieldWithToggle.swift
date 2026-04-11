import SwiftUI

public struct SecureFieldWithToggle<Field: Hashable>: View {
    let title: String
    @Binding var text: String
    private let focus: FocusState<Field?>.Binding
    private let field: Field
    var textContentType: PlatformTextContentType?
    var submitLabel: SubmitLabel
    var onSubmit: (() -> Void)?

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
        self._text = text
        self.focus = focus
        self.field = field
        self.textContentType = textContentType
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    public var body: some View {
        FormFieldSecureInput(
            title: title,
            text: $text,
            focus: focus,
            field: field,
            textContentType: textContentType,
            submitLabel: submitLabel,
            onSubmit: onSubmit
        )
    }
}
