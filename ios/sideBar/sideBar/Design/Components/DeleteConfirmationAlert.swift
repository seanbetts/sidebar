import SwiftUI

extension View {
    func destructiveConfirmationAlert(
        title: String,
        isPresented: Binding<Bool>,
        message: String,
        confirmTitle: String,
        cancelTitle: String = "Cancel",
        confirmAsDefaultAction: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert(Text(title), isPresented: isPresented) {
            if confirmAsDefaultAction {
                Button(confirmTitle, role: .destructive) {
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button(confirmTitle, role: .destructive) {
                    onConfirm()
                }
            }
            Button(cancelTitle, role: .cancel) {
                onCancel()
            }
        } message: {
            Text(message)
        }
    }

    func deleteConfirmationAlert(
        title: String,
        isPresented: Binding<Bool>,
        message: String,
        confirmTitle: String = "Delete",
        cancelTitle: String = "Cancel",
        confirmAsDefaultAction: Bool = false,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        destructiveConfirmationAlert(
            title: title,
            isPresented: isPresented,
            message: message,
            confirmTitle: confirmTitle,
            cancelTitle: cancelTitle,
            confirmAsDefaultAction: confirmAsDefaultAction,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }

    func actionConfirmationDialog<Actions: View>(
        title: String,
        isPresented: Binding<Bool>,
        cancelTitle: String = "Cancel",
        onCancel: @escaping () -> Void = {},
        @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            actions()
            Button(cancelTitle, role: .cancel) {
                onCancel()
            }
        }
    }
}
