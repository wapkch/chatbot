import SwiftUI
import Combine

struct ConfigurationEditView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var configurationManager: ConfigurationManager

    // Configuration data
    let existingConfiguration: APIConfiguration?
    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var modelID: String = ""
    @State private var apiKey: String = ""
    @State private var isDefault: Bool = false
    @State private var systemPrompts: [String] = [""]

    // UI State
    @State private var isLoading = false
    @State private var isTesting = false
    @State private var testResult: OpenAIService.TestResult?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasLoadedAPIKey = false

    // Services
    @StateObject private var openAIService = OpenAIService()

    // Cancellables for async operations
    @State private var cancellables = Set<AnyCancellable>()

    var isEditing: Bool {
        existingConfiguration != nil
    }

    var title: String {
        isEditing ? "Edit Configuration" : "New Configuration"
    }

    var saveButtonTitle: String {
        isEditing ? "Update" : "Add"
    }

    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isLoading
    }

    var canTest: Bool {
        canSave && !isTesting
    }

    init(configurationManager: ConfigurationManager, configuration: APIConfiguration? = nil) {
        self.configurationManager = configurationManager
        self.existingConfiguration = configuration
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Configuration Details")) {
                    TextField("Name", text: $name)
                        .textContentType(.none)
                        .autocapitalization(.words)

                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    TextField("Model ID", text: $modelID)
                        .textContentType(.none)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)

                    if !isEditing {
                        Toggle("Set as Default", isOn: $isDefault)
                    }
                }

                Section(header: Text("System Prompts")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Define the AI's behavior and personality with multiple prompts")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ForEach(systemPrompts.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Prompt \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    if systemPrompts.count > 1 {
                                        Button(action: {
                                            systemPrompts.remove(at: index)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                    }
                                }

                                TextEditor(text: Binding(
                                    get: { systemPrompts[index] },
                                    set: { systemPrompts[index] = $0 }
                                ))
                                .frame(minHeight: 80, maxHeight: 150)
                                .padding(4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }

                        Button(action: {
                            systemPrompts.append("")
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add System Prompt")
                            }
                            .foregroundColor(.blue)
                        }
                    }
                }

                Section(header: Text("Test Configuration")) {
                    Button(action: testConfiguration) {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Testing...")
                            } else {
                                Image(systemName: "checkmark.circle")
                                Text("Test Connection")
                            }
                        }
                    }
                    .disabled(!canTest)

                    if let testResult = testResult {
                        HStack {
                            Image(systemName: testResult.isSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testResult.isSuccessful ? .green : .red)
                            Text(testResult.summary)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)

                        if testResult.isSuccessful {
                            Text("Response: \(testResult.responseContent.prefix(100))...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(footer: footerText) {}
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(saveButtonTitle) {
                        saveConfiguration()
                    }
                    .disabled(!canSave)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadConfiguration()
            }
        }
    }

    private var footerText: some View {
        Text("API keys are stored securely in the Keychain. Test the configuration to verify connectivity before saving.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func loadConfiguration() {
        guard let config = existingConfiguration else {
            // Set default values for new configuration
            name = ""
            baseURL = "https://api.openai.com/v1"
            modelID = "gpt-3.5-turbo"
            apiKey = ""
            systemPrompts = [""]
            isDefault = configurationManager.configurations.isEmpty
            return
        }

        // Load existing configuration
        name = config.name
        baseURL = config.baseURL
        modelID = config.modelID
        systemPrompts = config.systemPrompts.isEmpty ? [""] : config.systemPrompts
        isDefault = config.isDefault

        // Load API key asynchronously
        if !hasLoadedAPIKey {
            Task {
                if let key = await configurationManager.getAPIKey(for: config) {
                    await MainActor.run {
                        apiKey = key
                        hasLoadedAPIKey = true
                    }
                }
            }
        }
    }

    private func testConfiguration() {
        guard canTest else { return }

        isTesting = true
        testResult = nil

        let testConfig = APIConfiguration(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: modelID.trimmingCharacters(in: .whitespacesAndNewlines),
            systemPrompts: systemPrompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        // Temporarily store API key for testing
        Task {
            do {
                try await configurationManager.addConfiguration(testConfig, apiKey: apiKey)

                // Test the configuration
                await MainActor.run {
                    openAIService.testConfiguration(testConfig)
                        .receive(on: DispatchQueue.main)
                        .sink(
                            receiveCompletion: { completion in
                                isTesting = false
                                if case .failure(let error) = completion {
                                    testResult = OpenAIService.TestResult(
                                        isSuccessful: false,
                                        responseContent: error.localizedDescription,
                                        responseTime: Date(),
                                        configuration: testConfig
                                    )
                                }
                            },
                            receiveValue: { result in
                                testResult = result
                            }
                        )
                        .store(in: &cancellables)
                }

                // Clean up temporary configuration if this is a new one
                if existingConfiguration == nil {
                    try await configurationManager.deleteConfiguration(testConfig)
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func saveConfiguration() {
        guard canSave else { return }

        isLoading = true

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSystemPrompts = systemPrompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        Task {
            do {
                if let existingConfig = existingConfiguration {
                    // Update existing configuration
                    let updatedConfig = APIConfiguration(
                        id: existingConfig.id,
                        name: trimmedName,
                        baseURL: trimmedBaseURL,
                        modelID: trimmedModelID,
                        isDefault: existingConfig.isDefault,
                        systemPrompts: trimmedSystemPrompts
                    )

                    // Only update API key if it's different from placeholder
                    let newAPIKey = trimmedAPIKey != String(repeating: "•", count: 12) ? trimmedAPIKey : nil
                    try await configurationManager.updateConfiguration(updatedConfig, apiKey: newAPIKey)
                } else {
                    // Add new configuration
                    let newConfig = APIConfiguration(
                        name: trimmedName,
                        baseURL: trimmedBaseURL,
                        modelID: trimmedModelID,
                        isDefault: isDefault,
                        systemPrompts: trimmedSystemPrompts
                    )

                    try await configurationManager.addConfiguration(newConfig, apiKey: trimmedAPIKey)

                    // Set as active if it's the default or first configuration
                    if isDefault || configurationManager.activeConfiguration == nil {
                        try await configurationManager.setActiveConfiguration(newConfig)
                    }
                }

                await MainActor.run {
                    isLoading = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Preview
struct ConfigurationEditView_Previews: PreviewProvider {
    static var previews: some View {
        let manager = ConfigurationManager()

        Group {
            // New configuration
            ConfigurationEditView(configurationManager: manager)
                .previewDisplayName("New Configuration")

            // Edit existing configuration
            ConfigurationEditView(
                configurationManager: manager,
                configuration: APIConfiguration.defaultConfigurations[0]
            )
            .previewDisplayName("Edit Configuration")
        }
    }
}