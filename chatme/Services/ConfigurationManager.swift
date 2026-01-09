import Foundation
import Combine
import Security

class ConfigurationManager: ObservableObject {
    @Published var configurations: [APIConfiguration] = []
    @Published var activeConfiguration: APIConfiguration?

    private let userDefaults = UserDefaults.standard
    private let configurationsKey = "APIConfigurations"
    private let activeConfigurationKey = "ActiveConfiguration"

    init() {
        loadConfigurations()
    }

    func loadConfigurations() {
        if let data = userDefaults.data(forKey: configurationsKey),
           let savedConfigs = try? JSONDecoder().decode([APIConfiguration].self, from: data) {
            configurations = savedConfigs
        } else {
            configurations = APIConfiguration.defaultConfigurations
            saveConfigurations()
        }

        if let activeID = userDefaults.string(forKey: activeConfigurationKey),
           let config = configurations.first(where: { $0.id.uuidString == activeID }) {
            activeConfiguration = config
        } else {
            activeConfiguration = configurations.first { $0.isDefault }
        }
    }

    func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            userDefaults.set(data, forKey: configurationsKey)
        }
    }

    func setActiveConfiguration(_ config: APIConfiguration) {
        activeConfiguration = config
        userDefaults.set(config.id.uuidString, forKey: activeConfigurationKey)
    }

    func addConfiguration(_ config: APIConfiguration) {
        configurations.append(config)
        saveConfigurations()
    }

    func updateConfiguration(_ config: APIConfiguration) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
            if activeConfiguration?.id == config.id {
                activeConfiguration = config
            }
            saveConfigurations()
        }
    }

    func deleteConfiguration(_ config: APIConfiguration) {
        configurations.removeAll { $0.id == config.id }
        if activeConfiguration?.id == config.id {
            activeConfiguration = configurations.first
        }
        saveConfigurations()
    }
}