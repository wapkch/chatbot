import Foundation

/// Compatibility extensions for ConfigurationManager to ease migration from synchronous to asynchronous API
extension ConfigurationManager {

    // MARK: - Legacy API Compatibility

    /// Legacy synchronous method for adding configuration (deprecated)
    /// - Parameter config: The configuration to add
    /// - Note: This method is deprecated. Use addConfiguration(_:apiKey:) async version instead.
    @available(*, deprecated, message: "Use addConfiguration(_:apiKey:) async version instead")
    func addConfiguration(_ config: APIConfiguration) {
        // For backward compatibility, add with empty API key
        // Users should migrate to the new async API
        Task {
            do {
                try await addConfiguration(config, apiKey: "")
            } catch {
                await MainActor.run {
                    self.lastError = error
                }
            }
        }
    }

    /// Legacy synchronous method for updating configuration (deprecated)
    /// - Parameter config: The configuration to update
    /// - Note: This method is deprecated. Use updateConfiguration(_:apiKey:) async version instead.
    @available(*, deprecated, message: "Use updateConfiguration(_:apiKey:) async version instead")
    func updateConfiguration(_ config: APIConfiguration) {
        Task {
            do {
                try await updateConfiguration(config, apiKey: nil)
            } catch {
                await MainActor.run {
                    self.lastError = error
                }
            }
        }
    }

    /// Legacy synchronous method for setting active configuration (deprecated)
    /// - Parameter config: The configuration to set as active
    /// - Note: This method is deprecated. Use setActiveConfiguration(_:) async version instead.
    @available(*, deprecated, message: "Use setActiveConfiguration(_:) async version instead")
    func setActiveConfiguration(_ config: APIConfiguration) {
        Task {
            do {
                try await setActiveConfiguration(config)
            } catch {
                await MainActor.run {
                    self.lastError = error
                }
            }
        }
    }

    /// Legacy synchronous method for deleting configuration (deprecated)
    /// - Parameter config: The configuration to delete
    /// - Note: This method is deprecated. Use deleteConfiguration(_:) async version instead.
    @available(*, deprecated, message: "Use deleteConfiguration(_:) async version instead")
    func deleteConfiguration(_ config: APIConfiguration) {
        Task {
            do {
                try await deleteConfiguration(config)
            } catch {
                await MainActor.run {
                    self.lastError = error
                }
            }
        }
    }

    /// Legacy synchronous method for loading configurations (deprecated)
    /// - Note: This method is deprecated. Configuration loading happens automatically in init.
    @available(*, deprecated, message: "Configuration loading happens automatically in init")
    func loadConfigurations() {
        Task {
            await loadConfigurations()
        }
    }

    /// Legacy synchronous method for saving configurations (deprecated)
    /// - Note: This method is deprecated. Configuration saving happens automatically when modifying configurations.
    @available(*, deprecated, message: "Configuration saving happens automatically when modifying configurations")
    func saveConfigurations() {
        // No-op for compatibility - saving now happens automatically
    }
}