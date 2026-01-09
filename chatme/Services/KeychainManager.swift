import Foundation
import Security

/// A secure manager for storing and retrieving sensitive data using iOS Keychain Services
class KeychainManager {

    // MARK: - Constants
    private struct Constants {
        static let service = "com.chatme.apikeys"
        static let accessGroup: String? = nil // Set if using app groups
    }

    // MARK: - Error Types
    enum KeychainError: Error, LocalizedError {
        case unexpectedData
        case unhandledError(status: OSStatus)
        case itemNotFound
        case duplicateItem

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                return "Unexpected data format in keychain"
            case .unhandledError(let status):
                return "Keychain error with status: \(status)"
            case .itemNotFound:
                return "Item not found in keychain"
            case .duplicateItem:
                return "Item already exists in keychain"
            }
        }
    }

    // MARK: - Singleton
    static let shared = KeychainManager()
    private init() {}

    // MARK: - Public Methods

    /// Store an API key securely in the keychain
    /// - Parameters:
    ///   - apiKey: The API key to store
    ///   - configurationID: The unique identifier for the configuration
    /// - Throws: KeychainError if the operation fails
    func storeAPIKey(_ apiKey: String, for configurationID: String) throws {
        let data = apiKey.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: configurationID,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // First try to update existing item
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: configurationID
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return // Successfully updated
        } else if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create new one
            let addStatus = SecItemAdd(query as CFDictionary, nil)

            if addStatus != errSecSuccess {
                throw KeychainError.unhandledError(status: addStatus)
            }
        } else {
            throw KeychainError.unhandledError(status: updateStatus)
        }
    }

    /// Retrieve an API key from the keychain
    /// - Parameter configurationID: The unique identifier for the configuration
    /// - Returns: The stored API key
    /// - Throws: KeychainError if the operation fails or item not found
    func retrieveAPIKey(for configurationID: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: configurationID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            } else {
                throw KeychainError.unhandledError(status: status)
            }
        }

        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }

        return apiKey
    }

    /// Delete an API key from the keychain
    /// - Parameter configurationID: The unique identifier for the configuration
    /// - Throws: KeychainError if the operation fails
    func deleteAPIKey(for configurationID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: configurationID
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    /// Check if an API key exists in the keychain
    /// - Parameter configurationID: The unique identifier for the configuration
    /// - Returns: True if the key exists, false otherwise
    func apiKeyExists(for configurationID: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: configurationID,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}