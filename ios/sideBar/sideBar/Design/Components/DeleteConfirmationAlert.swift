import SwiftUI

extension View {
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
}
