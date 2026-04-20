import Foundation

/// Keychain-backed staging store for pending provider-key secrets.
public final class SettingsPendingSecretStore {
    private var secrets: [String: Data] = [:]

    public init() {}

    public func stage(_ secret: Data) throws -> String {
        let reference = UUID().uuidString
        secrets[reference] = secret
        return reference
    }

    public func lookup(reference: String) throws -> Data {
        guard let secret = secrets[reference] else {
            throw SettingsPendingSecretStoreError.missingReference
        }
        return secret
    }

    public func delete(reference: String) throws {
        guard secrets.removeValue(forKey: reference) != nil else {
            throw SettingsPendingSecretStoreError.missingReference
        }
    }
}

enum SettingsPendingSecretStoreError: Error {
    case missingReference
}
