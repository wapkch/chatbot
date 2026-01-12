import Foundation

/// Configuration for API endpoints with validation and secure key management
struct APIConfiguration: Codable, Identifiable, Hashable {
    // MARK: - Properties
    private(set) var id: UUID
    var name: String
    var baseURL: String
    var modelID: String
    var isDefault: Bool = false
    var systemPrompts: [String] = []

    // MARK: - Constants
    struct Constants {
        static let minNameLength = 1
        static let maxNameLength = 100
        static let minModelIDLength = 1
        static let maxModelIDLength = 100
    }

    // MARK: - Initializers
    init(id: UUID = UUID(), name: String, baseURL: String, modelID: String, isDefault: Bool = false, systemPrompts: [String] = []) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.modelID = modelID
        self.isDefault = isDefault
        self.systemPrompts = systemPrompts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Codable Implementation
    enum CodingKeys: String, CodingKey {
        case id, name, baseURL, modelID, isDefault, systemPrompt, systemPrompts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode UUID with fallback for existing data
        if let idString = try? container.decode(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            self.id = uuid
        } else if let uuid = try? container.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            // Fallback for malformed data - create new UUID but log warning
            self.id = UUID()
            print("Warning: Invalid UUID found in APIConfiguration, generated new ID: \(self.id)")
        }

        self.name = try container.decode(String.self, forKey: .name)
        self.baseURL = try container.decode(String.self, forKey: .baseURL)
        self.modelID = try container.decode(String.self, forKey: .modelID)
        self.isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false

        // Support backward compatibility: try systemPrompts first, fall back to systemPrompt
        if let prompts = try? container.decodeIfPresent([String].self, forKey: .systemPrompts) {
            self.systemPrompts = prompts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else if let prompt = try? container.decodeIfPresent(String.self, forKey: .systemPrompt), !prompt.isEmpty {
            self.systemPrompts = [prompt]
        } else {
            self.systemPrompts = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(isDefault, forKey: .isDefault)
        try container.encode(systemPrompts, forKey: .systemPrompts)
    }

    // MARK: - Hashable Implementation
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: APIConfiguration, rhs: APIConfiguration) -> Bool {
        return lhs.id == rhs.id
    }

    // MARK: - Validation

    /// Validation errors for API Configuration
    enum ValidationError: Error, LocalizedError {
        case invalidName(String)
        case invalidBaseURL(String)
        case invalidModelID(String)

        var errorDescription: String? {
            switch self {
            case .invalidName(let reason):
                return "Invalid configuration name: \(reason)"
            case .invalidBaseURL(let reason):
                return "Invalid base URL: \(reason)"
            case .invalidModelID(let reason):
                return "Invalid model ID: \(reason)"
            }
        }
    }

    /// Validates the configuration data
    /// - Throws: ValidationError if any field is invalid
    func validate() throws {
        // Validate name
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidName("Name cannot be empty")
        }

        if name.count < Constants.minNameLength || name.count > Constants.maxNameLength {
            throw ValidationError.invalidName("Name must be between \(Constants.minNameLength) and \(Constants.maxNameLength) characters")
        }

        // Validate base URL
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            throw ValidationError.invalidBaseURL("Base URL cannot be empty")
        }

        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw ValidationError.invalidBaseURL("Base URL must be a valid HTTP or HTTPS URL")
        }

        // Validate model ID
        if modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.invalidModelID("Model ID cannot be empty")
        }

        if modelID.count < Constants.minModelIDLength || modelID.count > Constants.maxModelIDLength {
            throw ValidationError.invalidModelID("Model ID must be between \(Constants.minModelIDLength) and \(Constants.maxModelIDLength) characters")
        }
    }

    // MARK: - Default Configurations
    static let defaultConfigurations = [
        APIConfiguration(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            modelID: "gpt-3.5-turbo",
            isDefault: true
        ),
        APIConfiguration(
            name: "Azure OpenAI",
            baseURL: "https://your-resource.openai.azure.com",
            modelID: "gpt-35-turbo"
        )
    ]
}