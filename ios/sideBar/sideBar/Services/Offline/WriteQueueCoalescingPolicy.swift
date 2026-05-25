import Foundation

enum WriteQueueCoalescingPolicy {
    static func isTaskNotesUpdate(_ payload: Data) -> Bool {
        let decoder = JSONDecoder()
        guard let operation = try? decoder.decode(TaskOperationPayload.self, from: payload) else {
            return false
        }
        return operation.op.lowercased() == "notes"
    }

    static func mergedSettingsPatch(existing: Data, incoming: Data) -> Data? {
        let decoder = JSONDecoder()
        guard let existingPayload = try? decoder.decode(SettingsMutationPayload.self, from: existing),
              let incomingPayload = try? decoder.decode(SettingsMutationPayload.self, from: incoming),
              existingPayload.kind == .settingsPatch,
              incomingPayload.kind == .settingsPatch else {
            return nil
        }
        let merged = existingPayload.mergingSettingsPatch(with: incomingPayload)
        return try? JSONEncoder().encode(merged)
    }
}

private extension SettingsMutationPayload {
    func mergingSettingsPatch(with incoming: SettingsMutationPayload) -> SettingsMutationPayload {
        SettingsMutationPayload(
            communicationStyle: incoming.communicationStyle ?? communicationStyle,
            workingRelationship: incoming.workingRelationship ?? workingRelationship,
            name: incoming.name ?? name,
            jobTitle: incoming.jobTitle ?? jobTitle,
            employer: incoming.employer ?? employer,
            dateOfBirth: incoming.includeDateOfBirth ? incoming.dateOfBirth : dateOfBirth,
            gender: incoming.gender ?? gender,
            pronouns: incoming.pronouns ?? pronouns,
            location: incoming.location ?? location,
            notificationPreferences: incoming.notificationPreferences ?? notificationPreferences,
            assistantIdentity: incoming.assistantIdentity ?? assistantIdentity,
            aiPrimaryProvider: incoming.aiPrimaryProvider ?? aiPrimaryProvider,
            enabledSkills: incoming.enabledSkills ?? enabledSkills,
            includeDateOfBirth: includeDateOfBirth || incoming.includeDateOfBirth
        )
    }
}
