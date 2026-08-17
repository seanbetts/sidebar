import Foundation

extension AppEnvironment {
    var taskNotificationAuthContext: TaskNotificationAuthContext? {
        guard authState == .active || authState == .staleRecoverable,
              let accountId = currentAuthUserId,
              let cacheScopeAccountId = storage.userDefaults.string(
                forKey: AppStorageKeys.cacheScopeUserId
              ),
              TaskNotificationContract.accountIdentifier(
                accountId,
                matches: cacheScopeAccountId
              ),
              let currentAccountUUID = UUID(uuidString: accountId),
              let accountScope = taskNotificationAccountScopeCoordinator.currentScope,
              accountScope.accountId == currentAccountUUID else {
            return nil
        }
        return TaskNotificationAuthContext(
            authState: authState,
            accountId: accountId,
            generationId: accountScope.generationId
        )
    }

    func synchronizeTaskNotificationAccountScope() {
        guard authState == .active || authState == .staleRecoverable,
              let accountId = currentAuthUserId,
              let cacheScopeAccountId = storage.userDefaults.string(
                forKey: AppStorageKeys.cacheScopeUserId
              ),
              TaskNotificationContract.accountIdentifier(
                accountId,
                matches: cacheScopeAccountId
              ) else {
            taskNotificationAccountScopeCoordinator.invalidate()
            return
        }
        let defaults = storage.userDefaults
        let persistedGenerationId = defaults.string(
            forKey: AppStorageKeys.taskNotificationAccountGenerationId
        ).flatMap(UUID.init(uuidString:))
        guard let scope = taskNotificationAccountScopeCoordinator.activate(
            accountId: accountId,
            generationId: persistedGenerationId
        ) else {
            taskNotificationAccountScopeCoordinator.invalidate()
            return
        }
        if persistedGenerationId != scope.generationId {
            defaults.set(
                scope.generationId.uuidString,
                forKey: AppStorageKeys.taskNotificationAccountGenerationId
            )
        }
    }
}
