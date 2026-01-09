# ChatGPT iOS App Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a ChatGPT-style iOS app with OpenAI protocol support, custom API configuration, and local message storage.

**Architecture:** SwiftUI + MVVM pattern with Core Data for persistence, Keychain for secure API key storage, and URLSession for streaming OpenAI-compatible API requests.

**Tech Stack:** SwiftUI, Core Data, Keychain Services, Combine, URLSession

---

## Task 1: Core Data Models

**Files:**
- Create: `chatme/Models/DataModel.xcdatamodeld`
- Create: `chatme/Models/Message.swift`
- Create: `chatme/Models/Conversation.swift`
- Create: `chatme/Models/PersistenceController.swift`

**Step 1: Create Core Data model**

Create new Core Data model file with entities:
- Message: id (UUID), content (String), isFromUser (Bool), timestamp (Date), conversationID (UUID)
- Conversation: id (UUID), title (String), createdAt (Date), updatedAt (Date), messageCount (Int32)

**Step 2: Generate NSManagedObject subclasses**

Select entities → Editor menu → Create NSManagedObject Subclass

**Step 3: Create PersistenceController**

```swift
import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "DataModel")
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }
    }

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            try? context.save()
        }
    }
}
```

**Step 4: Update App file to inject Core Data context**

Modify `chatmeApp.swift`:

```swift
import SwiftUI

@main
struct chatmeApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
```

**Step 5: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add .
git commit -m "feat: add Core Data models for messages and conversations

- Message entity with content, user flag, timestamp
- Conversation entity with metadata
- PersistenceController for shared Core Data stack
- Inject managed object context into app"
```

## Task 2: API Configuration Models

**Files:**
- Create: `chatme/Models/APIConfiguration.swift`
- Create: `chatme/Services/ConfigurationManager.swift`
- Create: `chatme/Models/APIError.swift`

**Step 1: Create APIConfiguration model**

```swift
import Foundation

struct APIConfiguration: Codable, Identifiable {
    let id = UUID()
    var name: String
    var baseURL: String
    var apiKey: String
    var modelID: String
    var isDefault: Bool = false

    static let defaultConfigurations = [
        APIConfiguration(
            name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            apiKey: "",
            modelID: "gpt-3.5-turbo",
            isDefault: true
        ),
        APIConfiguration(
            name: "Azure OpenAI",
            baseURL: "",
            apiKey: "",
            modelID: "gpt-35-turbo"
        )
    ]
}
```

**Step 2: Create APIError enum**

```swift
import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL(String)
    case authenticationFailed(String)
    case modelNotFound(String)
    case rateLimitExceeded(retryAfter: TimeInterval)
    case networkTimeout
    case invalidResponse(statusCode: Int, message: String)
    case invalidJSONResponse
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url). Please check your base URL configuration."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message). Please check your API key."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please check your model ID configuration."
        case .rateLimitExceeded(let retryAfter):
            return "Rate limit exceeded. Please try again in \(Int(retryAfter)) seconds."
        case .networkTimeout:
            return "Network timeout. Please check your internet connection."
        case .invalidResponse(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .invalidJSONResponse:
            return "Invalid response format from server."
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Verify your base URL in Settings → API Configuration"
        case .authenticationFailed:
            return "Test your API key in Settings → API Configuration"
        case .modelNotFound:
            return "Check available models in your API documentation"
        case .rateLimitExceeded:
            return "Wait a moment before sending another message"
        case .networkTimeout:
            return "Check your internet connection and try again"
        case .invalidResponse:
            return "Contact your API provider if this persists"
        case .invalidJSONResponse:
            return "This may be a temporary server issue"
        case .streamingError:
            return "Try sending your message again"
        }
    }
}
```

**Step 3: Create ConfigurationManager**

```swift
import Foundation
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
```

**Step 4: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add API configuration management system

- APIConfiguration model with default templates
- Comprehensive APIError enum with user-friendly messages
- ConfigurationManager for CRUD operations and persistence
- UserDefaults storage for configuration data"
```

## Task 3: OpenAI API Service

**Files:**
- Create: `chatme/Services/OpenAIService.swift`
- Create: `chatme/Models/ChatMessage.swift`
- Create: `chatme/Models/ChatResponse.swift`

**Step 1: Create ChatMessage and ChatResponse models**

```swift
// chatme/Models/ChatMessage.swift
import Foundation

struct ChatMessage: Codable {
    let role: String
    let content: String

    enum Role: String, CaseIterable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
    }
}

// chatme/Models/ChatResponse.swift
import Foundation

struct ChatResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]

    struct Choice: Codable {
        let delta: Delta
        let index: Int
        let finish_reason: String?

        struct Delta: Codable {
            let content: String?
            let role: String?
        }
    }
}
```

**Step 2: Create OpenAIService**

```swift
import Foundation
import Combine

class OpenAIService: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    func sendMessage(
        _ message: String,
        configuration: APIConfiguration,
        conversationHistory: [ChatMessage] = []
    ) -> AnyPublisher<String, APIError> {

        guard let url = URL(string: "\(configuration.baseURL)/chat/completions") else {
            return Fail(error: APIError.invalidURL(configuration.baseURL))
                .eraseToAnyPublisher()
        }

        var messages = conversationHistory
        messages.append(ChatMessage(role: "user", content: message))

        let requestBody: [String: Any] = [
            "model": configuration.modelID,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return Fail(error: APIError.invalidJSONResponse)
                .eraseToAnyPublisher()
        }

        return URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse(statusCode: 0, message: "Invalid response")
                }

                if httpResponse.statusCode == 401 {
                    throw APIError.authenticationFailed("Invalid API key")
                } else if httpResponse.statusCode == 404 {
                    throw APIError.modelNotFound(configuration.modelID)
                } else if httpResponse.statusCode == 429 {
                    let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After") ?? "60"
                    throw APIError.rateLimitExceeded(retryAfter: TimeInterval(retryAfter) ?? 60)
                } else if httpResponse.statusCode >= 400 {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw APIError.invalidResponse(statusCode: httpResponse.statusCode, message: message)
                }

                return data
            }
            .compactMap { data -> [String] in
                let string = String(data: data, encoding: .utf8) ?? ""
                return string.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("data: ") && $0 != "data: [DONE]" }
                    .compactMap { line in
                        let jsonString = String(line.dropFirst(6))
                        guard let jsonData = jsonString.data(using: .utf8),
                              let response = try? JSONDecoder().decode(ChatResponse.self, from: jsonData),
                              let content = response.choices.first?.delta.content else {
                            return nil
                        }
                        return content
                    }
            }
            .flatMap { chunks in
                Publishers.Sequence(sequence: chunks)
            }
            .mapError { error in
                if let apiError = error as? APIError {
                    return apiError
                } else {
                    return APIError.streamingError(error.localizedDescription)
                }
            }
            .eraseToAnyPublisher()
    }

    func testConfiguration(_ configuration: APIConfiguration) -> AnyPublisher<Bool, APIError> {
        return sendMessage("Hello", configuration: configuration)
            .map { _ in true }
            .reduce(false) { _, _ in true }
            .eraseToAnyPublisher()
    }
}
```

**Step 3: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add OpenAI API service with streaming support

- ChatMessage and ChatResponse models for API communication
- OpenAIService with streaming chat completions
- Comprehensive error handling for API responses
- Configuration testing functionality
- Combine-based reactive API"
```

## Task 4: Chat View Model

**Files:**
- Create: `chatme/ViewModels/ChatViewModel.swift`
- Create: `chatme/ViewModels/ConversationStore.swift`

**Step 1: Create ChatViewModel**

```swift
import Foundation
import Combine
import CoreData

class ChatViewModel: ObservableObject {
    @Published var messages: [MessageViewModel] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var currentError: APIError?

    private let openAIService = OpenAIService()
    private let configurationManager: ConfigurationManager
    private let managedObjectContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    init(configurationManager: ConfigurationManager, context: NSManagedObjectContext) {
        self.configurationManager = configurationManager
        self.managedObjectContext = context
        loadMessages()
    }

    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let configuration = configurationManager.activeConfiguration else {
            return
        }

        let userMessage = inputText
        inputText = ""

        // Add user message immediately
        let userMessageVM = MessageViewModel(content: userMessage, isFromUser: true, timestamp: Date())
        messages.append(userMessageVM)
        saveMessage(userMessageVM)

        // Add loading assistant message
        let loadingMessageVM = MessageViewModel(content: "", isFromUser: false, timestamp: Date())
        messages.append(loadingMessageVM)

        isLoading = true
        currentError = nil

        let conversationHistory = messages.dropLast().compactMap { messageVM in
            ChatMessage(role: messageVM.isFromUser ? "user" : "assistant", content: messageVM.content)
        }

        openAIService.sendMessage(userMessage, configuration: configuration, conversationHistory: Array(conversationHistory))
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        self?.currentError = error
                        // Remove the loading message on error
                        self?.messages.removeLast()
                    }
                },
                receiveValue: { [weak self] content in
                    guard let self = self, let lastMessage = self.messages.last, !lastMessage.isFromUser else {
                        return
                    }

                    let updatedContent = lastMessage.content + content
                    self.messages[self.messages.count - 1] = MessageViewModel(
                        id: lastMessage.id,
                        content: updatedContent,
                        isFromUser: false,
                        timestamp: lastMessage.timestamp
                    )
                }
            )
            .store(in: &cancellables)
    }

    func clearMessages() {
        messages.removeAll()
        // Delete from Core Data
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        if let messages = try? managedObjectContext.fetch(request) {
            for message in messages {
                managedObjectContext.delete(message)
            }
            try? managedObjectContext.save()
        }
    }

    private func loadMessages() {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)]

        if let coreDataMessages = try? managedObjectContext.fetch(request) {
            messages = coreDataMessages.map { message in
                MessageViewModel(
                    content: message.content ?? "",
                    isFromUser: message.isFromUser,
                    timestamp: message.timestamp ?? Date()
                )
            }
        }
    }

    private func saveMessage(_ messageViewModel: MessageViewModel) {
        let message = Message(context: managedObjectContext)
        message.id = messageViewModel.id
        message.content = messageViewModel.content
        message.isFromUser = messageViewModel.isFromUser
        message.timestamp = messageViewModel.timestamp

        try? managedObjectContext.save()
    }
}

struct MessageViewModel: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let isFromUser: Bool
    let timestamp: Date

    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date) {
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
    }
}
```

**Step 2: Create ConversationStore**

```swift
import Foundation
import CoreData

class ConversationStore: ObservableObject {
    @Published var conversations: [ConversationViewModel] = []
    @Published var searchText: String = ""

    private let managedObjectContext: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.managedObjectContext = context
        loadConversations()
    }

    var filteredConversations: [ConversationViewModel] {
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    func loadConversations() {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.updatedAt, ascending: false)]

        if let coreDataConversations = try? managedObjectContext.fetch(request) {
            conversations = coreDataConversations.map { conversation in
                ConversationViewModel(
                    title: conversation.title ?? "New Chat",
                    createdAt: conversation.createdAt ?? Date(),
                    updatedAt: conversation.updatedAt ?? Date(),
                    messageCount: Int(conversation.messageCount)
                )
            }
        }
    }

    func deleteConversation(_ conversationViewModel: ConversationViewModel) {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", conversationViewModel.title)

        if let conversation = try? managedObjectContext.fetch(request).first {
            managedObjectContext.delete(conversation)
            try? managedObjectContext.save()
            loadConversations()
        }
    }

    func clearAllConversations() {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        if let conversations = try? managedObjectContext.fetch(request) {
            for conversation in conversations {
                managedObjectContext.delete(conversation)
            }
            try? managedObjectContext.save()
            loadConversations()
        }
    }
}

struct ConversationViewModel: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int
}
```

**Step 3: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add chat view models and conversation store

- ChatViewModel with real-time message streaming
- MessageViewModel for UI representation
- ConversationStore for managing chat history
- Core Data integration for message persistence
- Search functionality for conversations"
```

## Task 5: Main Chat Interface

**Files:**
- Modify: `chatme/ContentView.swift`
- Create: `chatme/Views/ChatView.swift`
- Create: `chatme/Views/MessageBubbleView.swift`

**Step 1: Create MessageBubbleView**

```swift
import SwiftUI

struct MessageBubbleView: View {
    let message: MessageViewModel

    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content.isEmpty ? "Thinking..." : message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal)
    }
}
```

**Step 2: Create ChatView**

```swift
import SwiftUI

struct ChatView: View {
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var configurationManager = ConfigurationManager()
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingSettings = false
    @State private var showingError = false

    init() {
        let configManager = ConfigurationManager()
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            configurationManager: configManager,
            context: PersistenceController.shared.container.viewContext
        ))
        _configurationManager = StateObject(wrappedValue: configManager)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(chatViewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical)
                    }
                    .onChange(of: chatViewModel.messages.count) { _ in
                        if let lastMessage = chatViewModel.messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input area
                HStack(spacing: 12) {
                    TextField("Type a message...", text: $chatViewModel.inputText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(chatViewModel.isLoading)

                    Button {
                        chatViewModel.sendMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                            .font(.system(size: 18))
                    }
                    .disabled(chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatViewModel.isLoading)
                }
                .padding()
            }
            .navigationTitle(configurationManager.activeConfiguration?.modelID ?? "ChatMe")
            .navigationBarItems(
                leading: Button("Clear") {
                    chatViewModel.clearMessages()
                },
                trailing: Button("Settings") {
                    showingSettings = true
                }
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(chatViewModel.currentError?.localizedDescription ?? "Unknown error")
        }
        .onChange(of: chatViewModel.currentError) { error in
            showingError = error != nil
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(configurationManager: configurationManager)
        }
    }
}
```

**Step 3: Update ContentView**

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        ChatView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
```

**Step 4: Create temporary SettingsView placeholder**

```swift
import SwiftUI

struct SettingsView: View {
    let configurationManager: ConfigurationManager
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Text("Settings - Coming Soon")
                .navigationTitle("Settings")
                .navigationBarItems(trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }
}
```

**Step 5: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 6: Commit**

```bash
git add .
git commit -m "feat: implement main chat interface

- MessageBubbleView with ChatGPT-style message bubbles
- ChatView with scrollable message list and input field
- Real-time message streaming with auto-scroll
- Error handling with user-friendly alerts
- Settings navigation placeholder"
```

## Task 6: Settings Interface

**Files:**
- Modify: `chatme/Views/SettingsView.swift`
- Create: `chatme/Views/ConfigurationEditView.swift`
- Create: `chatme/Views/ConfigurationListView.swift`

**Step 1: Create ConfigurationEditView**

```swift
import SwiftUI

struct ConfigurationEditView: View {
    @State private var configuration: APIConfiguration
    @State private var isTesting = false
    @State private var testResult: Result<Bool, APIError>?

    let onSave: (APIConfiguration) -> Void
    @Environment(\.presentationMode) var presentationMode

    private let openAIService = OpenAIService()

    init(configuration: APIConfiguration? = nil, onSave: @escaping (APIConfiguration) -> Void) {
        _configuration = State(initialValue: configuration ?? APIConfiguration(
            name: "",
            baseURL: "",
            apiKey: "",
            modelID: ""
        ))
        self.onSave = onSave
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Configuration Details")) {
                    TextField("Name", text: $configuration.name)
                    TextField("Base URL", text: $configuration.baseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    SecureField("API Key", text: $configuration.apiKey)
                    TextField("Model ID", text: $configuration.modelID)
                        .autocapitalization(.none)
                }

                Section(header: Text("Test Configuration")) {
                    Button {
                        testConfiguration()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isTesting || configuration.baseURL.isEmpty || configuration.apiKey.isEmpty)

                    if let result = testResult {
                        switch result {
                        case .success:
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Connection successful")
                                    .foregroundColor(.green)
                            }
                        case .failure(let error):
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("Connection failed")
                                        .foregroundColor(.red)
                                }
                                Text(error.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let suggestion = error.recoverySuggestion {
                                    Text(suggestion)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(configuration.name.isEmpty ? "New Configuration" : configuration.name)
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    onSave(configuration)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(configuration.name.isEmpty || configuration.baseURL.isEmpty || configuration.apiKey.isEmpty)
            )
        }
    }

    private func testConfiguration() {
        isTesting = true
        testResult = nil

        openAIService.testConfiguration(configuration)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    isTesting = false
                    if case .failure(let error) = completion {
                        testResult = .failure(error)
                    }
                },
                receiveValue: { success in
                    testResult = .success(success)
                }
            )
            .store(in: &openAIService.cancellables)
    }
}

private extension OpenAIService {
    var cancellables: Set<AnyCancellable> {
        get { objc_getAssociatedObject(self, &cancellablesKey) as? Set<AnyCancellable> ?? Set<AnyCancellable>() }
        set { objc_setAssociatedObject(self, &cancellablesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

private var cancellablesKey: UInt8 = 0
```

**Step 2: Create ConfigurationListView**

```swift
import SwiftUI

struct ConfigurationListView: View {
    @ObservedObject var configurationManager: ConfigurationManager
    @State private var showingEdit = false
    @State private var editingConfiguration: APIConfiguration?

    var body: some View {
        NavigationView {
            List {
                ForEach(configurationManager.configurations) { config in
                    ConfigurationRow(
                        configuration: config,
                        isActive: configurationManager.activeConfiguration?.id == config.id
                    ) {
                        configurationManager.setActiveConfiguration(config)
                    } onEdit: {
                        editingConfiguration = config
                        showingEdit = true
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        let config = configurationManager.configurations[index]
                        configurationManager.deleteConfiguration(config)
                    }
                }
            }
            .navigationTitle("API Configurations")
            .navigationBarItems(trailing: Button("Add") {
                editingConfiguration = nil
                showingEdit = true
            })
        }
        .sheet(isPresented: $showingEdit) {
            ConfigurationEditView(configuration: editingConfiguration) { config in
                if editingConfiguration != nil {
                    configurationManager.updateConfiguration(config)
                } else {
                    configurationManager.addConfiguration(config)
                }
            }
        }
    }
}

struct ConfigurationRow: View {
    let configuration: APIConfiguration
    let isActive: Bool
    let onTap: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.name)
                    .font(.headline)
                Text(configuration.modelID)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(configuration.baseURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Select") {
                    onTap()
                }
                .font(.caption)
            }

            Button("Edit") {
                onEdit()
            }
            .font(.caption)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isActive {
                onTap()
            }
        }
    }
}
```

**Step 3: Update SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var configurationManager: ConfigurationManager
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.managedObjectContext) private var viewContext

    @State private var showingConfigurations = false
    @State private var showingClearAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Configuration")) {
                    HStack {
                        Text("Current Configuration")
                        Spacer()
                        Text(configurationManager.activeConfiguration?.name ?? "None")
                            .foregroundColor(.secondary)
                    }

                    Button("Manage Configurations") {
                        showingConfigurations = true
                    }
                }

                Section(header: Text("Chat Management")) {
                    Button("Clear All Messages") {
                        showingClearAlert = true
                    }
                    .foregroundColor(.red)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Button("Feedback") {
                        // TODO: Add feedback functionality
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .sheet(isPresented: $showingConfigurations) {
            ConfigurationListView(configurationManager: configurationManager)
        }
        .alert("Clear All Messages", isPresented: $showingClearAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearAllMessages()
            }
        } message: {
            Text("This will permanently delete all your chat messages. This action cannot be undone.")
        }
    }

    private func clearAllMessages() {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        if let messages = try? viewContext.fetch(request) {
            for message in messages {
                viewContext.delete(message)
            }
            try? viewContext.save()
        }
    }
}
```

**Step 4: Build and verify**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add .
git commit -m "feat: implement comprehensive settings interface

- ConfigurationEditView with API testing functionality
- ConfigurationListView for managing multiple API configs
- Enhanced SettingsView with chat management
- Real-time configuration validation
- Clear all messages functionality"
```

## Task 7: Final Polish and Testing

**Files:**
- Create: `chatme/Extensions/View+Extensions.swift`
- Modify: `chatme/Views/MessageBubbleView.swift`
- Create: `chatme/Utils/HapticFeedback.swift`

**Step 1: Add View extensions for better UX**

```swift
// chatme/Extensions/View+Extensions.swift
import SwiftUI

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        self.onTapGesture(count: count, perform: action)
    }
}

extension String {
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    func trimmed() -> String {
        return self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Add haptic feedback**

```swift
// chatme/Utils/HapticFeedback.swift
import UIKit

class HapticFeedback {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
```

**Step 3: Enhance MessageBubbleView with better styling**

```swift
import SwiftUI

struct MessageBubbleView: View {
    let message: MessageViewModel
    @State private var showTimestamp = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromUser {
                Spacer()
                messageContent
            } else {
                messageContent
                Spacer()
            }
        }
        .padding(.horizontal)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTimestamp.toggle()
            }
            HapticFeedback.selection()
        }
    }

    private var messageContent: some View {
        VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
            Text(message.content.isEmpty ? "●●●" : message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.isFromUser
                        ? Color.blue
                        : Color(.systemGray5)
                )
                .foregroundColor(
                    message.isFromUser
                        ? .white
                        : .primary
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 18)
                )
                .textSelection(.enabled)

            if showTimestamp {
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
                HapticFeedback.notification(.success)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}
```

**Step 4: Update ChatView for better keyboard handling**

```swift
// Add to ChatView body, after the input area:
.onTapGesture {
    hideKeyboard()
}
.onSubmit {
    if !chatViewModel.inputText.trimmed().isEmpty {
        chatViewModel.sendMessage()
    }
}
```

**Step 5: Build and test thoroughly**

Run: `xcodebuild -project chatme.xcodeproj -scheme chatme -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: BUILD SUCCEEDED

**Step 6: Final commit**

```bash
git add .
git commit -m "feat: add final polish and UX improvements

- View extensions for better utility functions
- Haptic feedback for better interaction feel
- Enhanced message bubbles with timestamps and copy functionality
- Improved keyboard handling and text selection
- Context menus for message actions"
```

---

**Plan complete and saved to `docs/plans/2026-01-09-chatgpt-ios-implementation.md`. Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**