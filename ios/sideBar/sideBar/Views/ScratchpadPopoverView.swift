import SwiftUI

public struct ScratchpadPopoverView: View {
    @StateObject private var viewModel: ScratchpadViewModel
    @State private var draft: String = ""
    @State private var isSaving: Bool = false

    public init(api: any ScratchpadProviding, cache: CacheClient) {
        _viewModel = StateObject(wrappedValue: ScratchpadViewModel(api: api, cache: cache))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scratchpad")
                .font(.headline)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextEditor(text: $draft)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2))
                )

            HStack {
                Spacer()
                Button("Save") {
                    Task {
                        isSaving = true
                        await viewModel.update(content: draft, mode: .replace)
                        isSaving = false
                    }
                }
                .disabled(isSaving)
            }
        }
        .padding(16)
        .task {
            await viewModel.load()
            draft = viewModel.scratchpad?.content ?? ""
        }
    }
}
