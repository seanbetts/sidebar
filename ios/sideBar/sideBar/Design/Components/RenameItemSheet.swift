import SwiftUI

struct RenameItemSheet: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField(placeholder, text: $text)
                    .submitLabel(.done)
                    .onSubmit {
                        confirm()
                    }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        text = ""
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        confirm()
                    }
                    .disabled(text.trimmed.isEmpty)
                }
            }
        }
    }

    private func confirm() {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        text = ""
        onConfirm(trimmed)
        dismiss()
    }
}
