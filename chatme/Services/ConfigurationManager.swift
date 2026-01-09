import Foundation
import Combine
import Security

/// Thread-safe manager for API configurations with secure keychain storage
@MainActor
class ConfigurationManager: ObservableObject {

    // MARK: - Published Properties
    @Published private(set) var configurations: [APIConfiguration] = []
    @Published private(set) var activeConfiguration: APIConfiguration?
    @Published private(set) var lastError: Error?

    // MARK: - Constants
    private struct Constants {
        static let configurationsKey = "APIConfigurations"
        static let activeConfigurationKey = "ActiveConfiguration"
        static let maxConfigurations = 50
    }

    // MARK: - Dependencies
    private let userDefaults: UserDefaults
    private let keychainManager: KeychainManager
    private let queue = DispatchQueue(label: "com.chatme.configuration-manager", qos: .userInitiated)

    // MARK: - Error Types
    enum ConfigurationError: Error, LocalizedError {
        case maxConfigurationsReached
        case configurationNotFound
        case encodingFailed(Error)
        case decodingFailed(Error)
        case keychainError(Error)
        case validationFailed(Error)
        case cannotDeleteLastConfiguration
        case cannotDeleteActiveConfiguration

        var errorDescription: String? {
            switch self {
            case .maxConfigurationsReached:
                return "Maximum number of configurations (\(Constants.maxConfigurations)) reached"
            case .configurationNotFound:
                return "Configuration not found"
            case .encodingFailed(let error):
                return "Failed to encode configurations: \(error.localizedDescription)"
            case .decodingFailed(let error):
                return "Failed to decode configurations: \(error.localizedDescription)"
            case .keychainError(let error):
                return "Keychain operation failed: \(error.localizedDescription)"
            case .validationFailed(let error):
                return "Configuration validation failed: \(error.localizedDescription)"
            case .cannotDeleteLastConfiguration:
                return "Cannot delete the last remaining configuration"
            case .cannotDeleteActiveConfiguration:
                return "Cannot delete the active configuration. Please select a different active configuration first."
            }
        }
    }

    // MARK: - Initializer

    /// Initialize with optional dependency injection for testing
    /// - Parameters:
    ///   - userDefaults: UserDefaults instance (default: .standard)
    ///   - keychainManager: KeychainManager instance (default: .shared)
    init(userDefaults: UserDefaults = .standard, keychainManager: KeychainManager = .shared) {
        self.userDefaults = userDefaults
        self.keychainManager = keychainManager
        Task {
            await loadConfigurations()
        }
    }

    // MARK: - Public Methods

    /// Load configurations from UserDefaults and set active configuration
    func loadConfigurations() async {
        do {
            try await queue.execute {
                await MainActor.run {
                    self.lastError = nil
                }

                let loadedConfigs: [APIConfiguration]

                if let data = self.userDefaults.data(forKey: Constants.configurationsKey) {
                    do {
                        loadedConfigs = try JSONDecoder().decode([APIConfiguration].self, from: data)
                    } catch {
                        await MainActor.run {
                            self.lastError = ConfigurationError.decodingFailed(error)
                        }
                        print("Failed to decode configurations, using defaults: \(error)")
                        loadedConfigs = APIConfiguration.defaultConfigurations
                        try await self.saveConfigurationsUnsafe(loadedConfigs)
                    }
                } else {
                    loadedConfigs = APIConfiguration.defaultConfigurations
                    try await self.saveConfigurationsUnsafe(loadedConfigs)
                }

                await MainActor.run {
                    self.configurations = loadedConfigs
                }

                // Set active configuration
                let activeID = self.userDefaults.string(forKey: Constants.activeConfigurationKey)
                let activeConfig: APIConfiguration?

                if let activeID = activeID,
                   let config = loadedConfigs.first(where: { $0.id.uuidString == activeID }) {
                    activeConfig = config
                } else {
                    activeConfig = loadedConfigs.first { $0.isDefault } ?? loadedConfigs.first
                    if let activeConfig = activeConfig {
                        self.userDefaults.set(activeConfig.id.uuidString, forKey: Constants.activeConfigurationKey)
                    }
                }

                await MainActor.run {
                    self.activeConfiguration = activeConfig
                }
            }
        } catch {
            await MainActor.run {
                self.lastError = error
            }
        }
    }

    /// Set the active configuration
    /// - Parameter config: The configuration to set as active
    func setActiveConfiguration(_ config: APIConfiguration) async throws {
        try await queue.execute {
            guard await MainActor.run(body: { self.configurations.contains(config) }) else {
                throw ConfigurationError.configurationNotFound
            }

            self.userDefaults.set(config.id.uuidString, forKey: Constants.activeConfigurationKey)

            await MainActor.run {
                self.activeConfiguration = config
                self.lastError = nil
            }
        }
    }

    /// Add a new configuration with API key
    /// - Parameters:
    ///   - config: The configuration to add
    ///   - apiKey: The API key to store securely
    func addConfiguration(_ config: APIConfiguration, apiKey: String) async throws {
        try await queue.execute {
            // Validate configuration
            try config.validate()

            // Check limits
            if await MainActor.run(body: { self.configurations.count }) >= Constants.maxConfigurations {
                throw ConfigurationError.maxConfigurationsReached
            }

            // Store API key in keychain
            do {
                try self.keychainManager.storeAPIKey(apiKey, for: config.id.uuidString)
            } catch {
                throw ConfigurationError.keychainError(error)
            }

            // Add configuration
            await MainActor.run {
                self.configurations.append(config)
            }

            try await self.saveConfigurationsUnsafe(await MainActor.run { self.configurations })

            await MainActor.run {
                self.lastError = nil
            }
        }
    }

    /// Update an existing configuration
    /// - Parameters:
    ///   - config: The updated configuration
    ///   - apiKey: Optional new API key (if nil, existing key is preserved)
    func updateConfiguration(_ config: APIConfiguration, apiKey: String? = nil) async throws {
        try await queue.execute {
            // Validate configuration
            try config.validate()

            guard let index = await MainActor.run(body: { self.configurations.firstIndex(where: { $0.id == config.id }) }) else {
                throw ConfigurationError.configurationNotFound
            }

            // Update API key if provided
            if let apiKey = apiKey {
                do {
                    try self.keychainManager.storeAPIKey(apiKey, for: config.id.uuidString)
                } catch {
                    throw ConfigurationError.keychainError(error)
                }
            }

            // Update configuration
            await MainActor.run {
                self.configurations[index] = config
                if self.activeConfiguration?.id == config.id {
                    self.activeConfiguration = config
                }
            }

            try await self.saveConfigurationsUnsafe(await MainActor.run { self.configurations })

            await MainActor.run {
                self.lastError = nil
            }
        }
    }

    /// Delete a configuration and its associated API key
    /// - Parameter config: The configuration to delete
    func deleteConfiguration(_ config: APIConfiguration) async throws {
        try await queue.execute {
            let currentConfigs = await MainActor.run { self.configurations }

            // Prevent deleting the last configuration
            if currentConfigs.count <= 1 {
                throw ConfigurationError.cannotDeleteLastConfiguration
            }

            // Prevent deleting active configuration
            let currentActive = await MainActor.run { self.activeConfiguration }
            if currentActive?.id == config.id {
                throw ConfigurationError.cannotDeleteActiveConfiguration
            }

            // Delete API key from keychain
            do {
                try self.keychainManager.deleteAPIKey(for: config.id.uuidString)
            } catch {
                // Log but don't fail - key might not exist
                print("Warning: Failed to delete API key from keychain: \(error)")
            }

            // Remove configuration
            await MainActor.run {
                self.configurations.removeAll { $0.id == config.id }
            }

            try await self.saveConfigurationsUnsafe(await MainActor.run { self.configurations })

            await MainActor.run {
                self.lastError = nil
            }
        }
    }

    /// Get the API key for a configuration
    /// - Parameter config: The configuration to get the key for
    /// - Returns: The API key or nil if not found
    func getAPIKey(for config: APIConfiguration) async -> String? {
        do {
            return try await queue.execute {
                return try self.keychainManager.retrieveAPIKey(for: config.id.uuidString)
            }
        } catch {
            await MainActor.run {
                self.lastError = ConfigurationError.keychainError(error)
            }
            return nil
        }
    }

    /// Check if an API key exists for a configuration
    /// - Parameter config: The configuration to check
    /// - Returns: True if API key exists
    func hasAPIKey(for config: APIConfiguration) async -> Bool {
        return await queue.execute {
            return self.keychainManager.apiKeyExists(for: config.id.uuidString)
        }
    }

    /// Clear the last error
    func clearError() {
        lastError = nil
    }

    // MARK: - Private Methods

    private func saveConfigurationsUnsafe(_ configs: [APIConfiguration]) async throws {
        do {
            let data = try JSONEncoder().encode(configs)
            userDefaults.set(data, forKey: Constants.configurationsKey)
        } catch {
            throw ConfigurationError.encodingFailed(error)
        }
    }
}

// MARK: - DispatchQueue Extension for async/await

private extension DispatchQueue {
    func execute<T>(_ work: @escaping () async throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            self.async {
                Task {
                    do {
                        let result = try await work()
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}