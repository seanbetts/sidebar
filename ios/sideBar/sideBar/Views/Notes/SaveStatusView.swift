import SwiftUI

struct SaveStatusView: View {
    @ObservedObject var editorViewModel: NotesEditorViewModel
    @State private var showSavedIndicator = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        Group {
            if editorViewModel.isReadOnly {
                statusRow(
                    text: "Read-only preview",
                    systemImage: "eye",
                    color: .secondary
                )
            } else if let saveError = editorViewModel.saveError {
                statusRow(
                    text: saveError,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .red
                )
            } else if editorViewModel.isSaving {
                statusRow(
                    text: "Saving...",
                    systemImage: nil,
                    color: .secondary,
                    showsProgress: true
                )
            } else if editorViewModel.isDirty {
                statusRow(
                    text: "Unsaved changes",
                    systemImage: "pencil",
                    color: .secondary
                )
            } else if shouldShowSaved, let label = lastSavedLabel() {
                statusRow(
                    text: "Saved \(label)",
                    systemImage: "clock",
                    color: .secondary
                )
            }
        }
        .onAppear {
            updateSavedIndicator()
        }
        .onChange(of: editorViewModel.lastSaved?.timeIntervalSince1970 ?? 0) { _, _ in
            updateSavedIndicator()
        }
        .onChange(of: editorViewModel.isDirty) { _, isDirty in
            if isDirty {
                hideSavedIndicator()
            }
        }
        .onChange(of: editorViewModel.isSaving) { _, isSaving in
            if isSaving {
                hideSavedIndicator()
            }
        }
        .onDisappear {
            hideTask?.cancel()
        }
    }

    private var shouldShowSaved: Bool {
        showSavedIndicator
            && !editorViewModel.isDirty
            && !editorViewModel.isSaving
            && editorViewModel.saveError == nil
            && !editorViewModel.isReadOnly
    }

    @ViewBuilder
    private func statusRow(
        text: String,
        systemImage: String?,
        color: Color,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 6) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(color)
        .accessibilityLabel(text)
    }

    private func lastSavedLabel() -> String? {
        guard let date = editorViewModel.lastSaved else { return nil }
        let now = Date()
        let diff = now.timeIntervalSince(date)
        if diff < 60 {
            return "just now"
        }
        if diff < 3600 {
            let minutes = Int(diff / 60)
            return "\(minutes)m ago"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func updateSavedIndicator() {
        guard editorViewModel.lastSaved != nil else {
            hideSavedIndicator()
            return
        }
        guard !editorViewModel.isDirty,
              !editorViewModel.isSaving,
              editorViewModel.saveError == nil,
              !editorViewModel.isReadOnly else {
            hideSavedIndicator()
            return
        }
        showSavedIndicator = true
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.showSavedIndicator = false
            }
        }
    }

    private func hideSavedIndicator() {
        showSavedIndicator = false
        hideTask?.cancel()
    }
}
