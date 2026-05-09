import sideBarShared

extension IngestionViewModel {
    func presentMutationFailure(_ error: Error, operation: String) {
        let presentation = ErrorMapping.presentation(
            for: error,
            operation: operation,
            requestKind: .foregroundMutation
        )
        presentMutationFailureMessage(presentation.message, isSilent: presentation.surface == .silent)
    }

    func presentMutationFailureMessage(_ message: String, isSilent: Bool = false) {
        errorMessage = nil
        guard !isSilent else { return }
        toastCenter.show(message: message)
    }
}
