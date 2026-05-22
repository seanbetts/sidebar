import Foundation

enum AsyncJobDomain: Equatable {
    case websiteSave
    case websiteTranscript
    case fileProcessing
}

struct AsyncJobStatus: Equatable {
    let rawValue: String

    var normalized: String {
        rawValue.normalizedAsyncJobStatus
    }
}

struct AsyncJobDescriptor: Equatable {
    let domain: AsyncJobDomain
    let entityId: String
    let jobId: String
    let terminalStatuses: Set<String>

    init(
        domain: AsyncJobDomain,
        entityId: String,
        jobId: String,
        terminalStatuses: Set<String>
    ) {
        self.domain = domain
        self.entityId = entityId
        self.jobId = jobId
        self.terminalStatuses = terminalStatuses.map(\.normalizedAsyncJobStatus).asSet
    }
}

enum AsyncJobProgressResult: Equatable {
    case active(status: String)
    case terminal(status: String, userMessage: String?)
    case unknownJob
}

private extension Array where Element == String {
    var asSet: Set<String> {
        Set(self)
    }
}

private extension String {
    var normalizedAsyncJobStatus: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
