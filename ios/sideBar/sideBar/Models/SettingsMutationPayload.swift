import Foundation

public struct SettingsMutationPayload: Codable, Equatable {
    public enum Kind: String, Codable {
        case settingsPatch
        case providerKeyUpsert
        case providerKeyDelete
        case providerKeyDisconnect
        case profileImageUpload
        case profileImageDelete
    }

    public let kind: Kind
    public let communicationStyle: String?
    public let workingRelationship: String?
    public let name: String?
    public let jobTitle: String?
    public let employer: String?
    public let dateOfBirth: String?
    public let gender: String?
    public let pronouns: String?
    public let location: String?
    public let notificationPreferences: NotificationPreferencesUpdate?
    public let assistantIdentity: AssistantIdentitySettings?
    public let aiPrimaryProvider: String?
    public let enabledSkills: [String]?
    public let includeDateOfBirth: Bool
    public let provider: String?
    public let rawSecretReference: String?
    public let providerKeyLast4: String?
    public let selectAsPrimaryProvider: Bool
    public let disconnectSource: ProviderKeyDisconnectSource?
    public let skillId: String?
    public let assetRef: String?
    public let contentType: String?
    public let filename: String?

    public init(
        communicationStyle: String? = nil,
        workingRelationship: String? = nil,
        name: String? = nil,
        jobTitle: String? = nil,
        employer: String? = nil,
        dateOfBirth: String? = nil,
        gender: String? = nil,
        pronouns: String? = nil,
        location: String? = nil,
        notificationPreferences: NotificationPreferencesUpdate? = nil,
        assistantIdentity: AssistantIdentitySettings? = nil,
        aiPrimaryProvider: String? = nil,
        enabledSkills: [String]? = nil,
        includeDateOfBirth: Bool = false
    ) {
        self.kind = .settingsPatch
        self.communicationStyle = communicationStyle
        self.workingRelationship = workingRelationship
        self.name = name
        self.jobTitle = jobTitle
        self.employer = employer
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.pronouns = pronouns
        self.location = location
        self.notificationPreferences = notificationPreferences
        self.assistantIdentity = assistantIdentity
        self.aiPrimaryProvider = aiPrimaryProvider
        self.enabledSkills = enabledSkills
        self.includeDateOfBirth = includeDateOfBirth
        self.provider = nil
        self.rawSecretReference = nil
        self.providerKeyLast4 = nil
        self.selectAsPrimaryProvider = false
        self.disconnectSource = nil
        self.skillId = nil
        self.assetRef = nil
        self.contentType = nil
        self.filename = nil
    }

    public static func providerKey(
        provider: String,
        rawSecretReference: String,
        providerKeyLast4: String? = nil,
        selectAsPrimaryProvider: Bool = false
    ) -> Self {
        Self(
            kind: .providerKeyUpsert,
            provider: provider,
            rawSecretReference: rawSecretReference,
            providerKeyLast4: providerKeyLast4,
            selectAsPrimaryProvider: selectAsPrimaryProvider
        )
    }

    public static func providerKeyDelete(provider: String) -> Self {
        Self(
            kind: .providerKeyDelete,
            provider: provider
        )
    }

    public static func providerKeyDisconnect(
        provider: String,
        source: ProviderKeyDisconnectSource,
        skillId: String? = nil
    ) -> Self {
        Self(
            kind: .providerKeyDisconnect,
            provider: provider,
            disconnectSource: source,
            skillId: skillId
        )
    }

    public static func profileImageUpload(
        assetRef: String,
        contentType: String,
        filename: String
    ) -> Self {
        Self(
            kind: .profileImageUpload,
            assetRef: assetRef,
            contentType: contentType,
            filename: filename
        )
    }

    public static var profileImageDelete: Self {
        Self(kind: .profileImageDelete)
    }

    public var entityId: String {
        switch kind {
        case .settingsPatch:
            return "settings"
        case .providerKeyUpsert:
            return provider ?? "provider-key"
        case .providerKeyDelete:
            return provider ?? "provider-key-delete"
        case .providerKeyDisconnect:
            return provider ?? "provider-key"
        case .profileImageUpload:
            return assetRef ?? "profile-image"
        case .profileImageDelete:
            return "profile-image"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case communicationStyle
        case workingRelationship
        case name
        case jobTitle
        case employer
        case dateOfBirth
        case gender
        case pronouns
        case location
        case notificationPreferences
        case assistantIdentity
        case aiPrimaryProvider
        case enabledSkills
        case includeDateOfBirth
        case provider
        case rawSecretReference
        case providerKeyLast4
        case selectAsPrimaryProvider
        case disconnectSource
        case skillId
        case assetRef
        case contentType
        case filename
    }

    private enum NotificationPreferencesCodingKeys: String, CodingKey {
        case taskRemindersEnabled = "task_reminders_enabled"
        case taskReminderTime = "task_reminder_time"
        case morningDigestEnabled = "morning_digest_enabled"
        case morningDigestTime = "morning_digest_time"
        case assistantReplyNotificationsEnabled = "assistant_reply_notifications_enabled"
        case assistantProactiveNotificationsEnabled = "assistant_proactive_notifications_enabled"
        case scheduleTimezone = "schedule_timezone"
    }

    private init(
        kind: Kind,
        communicationStyle: String? = nil,
        workingRelationship: String? = nil,
        name: String? = nil,
        jobTitle: String? = nil,
        employer: String? = nil,
        dateOfBirth: String? = nil,
        gender: String? = nil,
        pronouns: String? = nil,
        location: String? = nil,
        notificationPreferences: NotificationPreferencesUpdate? = nil,
        assistantIdentity: AssistantIdentitySettings? = nil,
        aiPrimaryProvider: String? = nil,
        enabledSkills: [String]? = nil,
        includeDateOfBirth: Bool = false,
        provider: String? = nil,
        rawSecretReference: String? = nil,
        providerKeyLast4: String? = nil,
        selectAsPrimaryProvider: Bool = false,
        disconnectSource: ProviderKeyDisconnectSource? = nil,
        skillId: String? = nil,
        assetRef: String? = nil,
        contentType: String? = nil,
        filename: String? = nil
    ) {
        self.kind = kind
        self.communicationStyle = communicationStyle
        self.workingRelationship = workingRelationship
        self.name = name
        self.jobTitle = jobTitle
        self.employer = employer
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.pronouns = pronouns
        self.location = location
        self.notificationPreferences = notificationPreferences
        self.assistantIdentity = assistantIdentity
        self.aiPrimaryProvider = aiPrimaryProvider
        self.enabledSkills = enabledSkills
        self.includeDateOfBirth = includeDateOfBirth
        self.provider = provider
        self.rawSecretReference = rawSecretReference
        self.providerKeyLast4 = providerKeyLast4
        self.selectAsPrimaryProvider = selectAsPrimaryProvider
        self.disconnectSource = disconnectSource
        self.skillId = skillId
        self.assetRef = assetRef
        self.contentType = contentType
        self.filename = filename
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(communicationStyle, forKey: .communicationStyle)
        try container.encodeIfPresent(workingRelationship, forKey: .workingRelationship)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(jobTitle, forKey: .jobTitle)
        try container.encodeIfPresent(employer, forKey: .employer)
        try container.encodeIfPresent(dateOfBirth, forKey: .dateOfBirth)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(pronouns, forKey: .pronouns)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encodeIfPresent(assistantIdentity, forKey: .assistantIdentity)
        try container.encodeIfPresent(aiPrimaryProvider, forKey: .aiPrimaryProvider)
        try container.encodeIfPresent(enabledSkills, forKey: .enabledSkills)
        try container.encode(includeDateOfBirth, forKey: .includeDateOfBirth)
        try container.encodeIfPresent(provider, forKey: .provider)
        try container.encodeIfPresent(rawSecretReference, forKey: .rawSecretReference)
        try container.encodeIfPresent(providerKeyLast4, forKey: .providerKeyLast4)
        try container.encode(selectAsPrimaryProvider, forKey: .selectAsPrimaryProvider)
        try container.encodeIfPresent(disconnectSource, forKey: .disconnectSource)
        try container.encodeIfPresent(skillId, forKey: .skillId)
        try container.encodeIfPresent(assetRef, forKey: .assetRef)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encodeIfPresent(filename, forKey: .filename)

        if let notificationPreferences {
            var notificationContainer = container.nestedContainer(
                keyedBy: NotificationPreferencesCodingKeys.self,
                forKey: .notificationPreferences
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.taskRemindersEnabled,
                forKey: .taskRemindersEnabled
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.taskReminderTime,
                forKey: .taskReminderTime
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.morningDigestEnabled,
                forKey: .morningDigestEnabled
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.morningDigestTime,
                forKey: .morningDigestTime
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.assistantReplyNotificationsEnabled,
                forKey: .assistantReplyNotificationsEnabled
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.assistantProactiveNotificationsEnabled,
                forKey: .assistantProactiveNotificationsEnabled
            )
            try notificationContainer.encodeIfPresent(
                notificationPreferences.scheduleTimezone,
                forKey: .scheduleTimezone
            )
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let communicationStyle = try container.decodeIfPresent(String.self, forKey: .communicationStyle)
        let workingRelationship = try container.decodeIfPresent(String.self, forKey: .workingRelationship)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let jobTitle = try container.decodeIfPresent(String.self, forKey: .jobTitle)
        let employer = try container.decodeIfPresent(String.self, forKey: .employer)
        let dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        let gender = try container.decodeIfPresent(String.self, forKey: .gender)
        let pronouns = try container.decodeIfPresent(String.self, forKey: .pronouns)
        let location = try container.decodeIfPresent(String.self, forKey: .location)
        let assistantIdentity = try container.decodeIfPresent(AssistantIdentitySettings.self, forKey: .assistantIdentity)
        let aiPrimaryProvider = try container.decodeIfPresent(String.self, forKey: .aiPrimaryProvider)
        let enabledSkills = try container.decodeIfPresent([String].self, forKey: .enabledSkills)
        let includeDateOfBirth = try container.decodeIfPresent(Bool.self, forKey: .includeDateOfBirth) ?? false
        let provider = try container.decodeIfPresent(String.self, forKey: .provider)
        let rawSecretReference = try container.decodeIfPresent(String.self, forKey: .rawSecretReference)
        let providerKeyLast4 = try container.decodeIfPresent(String.self, forKey: .providerKeyLast4)
        let selectAsPrimaryProvider = try container.decodeIfPresent(Bool.self, forKey: .selectAsPrimaryProvider) ?? false
        let disconnectSource = try container.decodeIfPresent(
            ProviderKeyDisconnectSource.self,
            forKey: .disconnectSource
        )
        let skillId = try container.decodeIfPresent(String.self, forKey: .skillId)
        let assetRef = try container.decodeIfPresent(String.self, forKey: .assetRef)
        let contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
        let filename = try container.decodeIfPresent(String.self, forKey: .filename)

        let notificationPreferences = try Self.decodeNotificationPreferences(from: container)

        self.init(
            kind: kind,
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            aiPrimaryProvider: aiPrimaryProvider,
            enabledSkills: enabledSkills,
            includeDateOfBirth: includeDateOfBirth,
            provider: provider,
            rawSecretReference: rawSecretReference,
            providerKeyLast4: providerKeyLast4,
            selectAsPrimaryProvider: selectAsPrimaryProvider,
            disconnectSource: disconnectSource,
            skillId: skillId,
            assetRef: assetRef,
            contentType: contentType,
            filename: filename
        )
    }

    private static func decodeNotificationPreferences(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NotificationPreferencesUpdate? {
        guard container.contains(.notificationPreferences) else {
            return nil
        }

        let notificationContainer = try container.nestedContainer(
            keyedBy: NotificationPreferencesCodingKeys.self,
            forKey: .notificationPreferences
        )
        let taskRemindersEnabled = try notificationContainer.decodeIfPresent(
            Bool.self,
            forKey: .taskRemindersEnabled
        )
        let taskReminderTime = try notificationContainer.decodeIfPresent(
            String.self,
            forKey: .taskReminderTime
        )
        let morningDigestEnabled = try notificationContainer.decodeIfPresent(
            Bool.self,
            forKey: .morningDigestEnabled
        )
        let morningDigestTime = try notificationContainer.decodeIfPresent(
            String.self,
            forKey: .morningDigestTime
        )
        let assistantReplyNotificationsEnabled = try notificationContainer.decodeIfPresent(
            Bool.self,
            forKey: .assistantReplyNotificationsEnabled
        )
        let assistantProactiveNotificationsEnabled = try notificationContainer.decodeIfPresent(
            Bool.self,
            forKey: .assistantProactiveNotificationsEnabled
        )
        let scheduleTimezone = try notificationContainer.decodeIfPresent(
            String.self,
            forKey: .scheduleTimezone
        )

        guard taskRemindersEnabled != nil
            || taskReminderTime != nil
            || morningDigestEnabled != nil
            || morningDigestTime != nil
            || assistantReplyNotificationsEnabled != nil
            || assistantProactiveNotificationsEnabled != nil
            || scheduleTimezone != nil else {
            return nil
        }

        return NotificationPreferencesUpdate(
            taskRemindersEnabled: taskRemindersEnabled,
            taskReminderTime: taskReminderTime,
            morningDigestEnabled: morningDigestEnabled,
            morningDigestTime: morningDigestTime,
            assistantReplyNotificationsEnabled: assistantReplyNotificationsEnabled,
            assistantProactiveNotificationsEnabled: assistantProactiveNotificationsEnabled,
            scheduleTimezone: scheduleTimezone
        )
    }
}

extension SettingsMutationPayload {
    func makeSettingsUpdate() -> SettingsUpdate {
        SettingsUpdate(
            communicationStyle: communicationStyle,
            workingRelationship: workingRelationship,
            name: name,
            jobTitle: jobTitle,
            employer: employer,
            dateOfBirth: dateOfBirth,
            gender: gender,
            pronouns: pronouns,
            location: location,
            notificationPreferences: notificationPreferences,
            assistantIdentity: assistantIdentity,
            aiPrimaryProvider: aiPrimaryProvider,
            enabledSkills: enabledSkills,
            includeDateOfBirth: includeDateOfBirth
        )
    }
}
