import Foundation
import Combine
import CoreData

class ChatViewModel: ObservableObject {
    @Published var messages: [MessageViewModel] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var currentError: APIError?

    private let openAIService: OpenAIService
    private let configurationManager: ConfigurationManager
    private let managedObjectContext: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()

    let conversationStore: ConversationStore

    init(configurationManager: ConfigurationManager, context: NSManagedObjectContext) {
        self.configurationManager = configurationManager
        self.managedObjectContext = context
        self.openAIService = OpenAIService(configurationManager: configurationManager)
        self.conversationStore = ConversationStore(context: context)
        loadMessages()
    }

    @MainActor
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
            ChatMessage(role: messageVM.isFromUser ? .user : .assistant, content: messageVM.content)
        }

        openAIService.sendMessage(userMessage, configuration: configuration, conversationHistory: Array(conversationHistory))
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    print("🔍 DEBUG: ChatViewModel completion: \(completion)")
                    self?.isLoading = false

                    switch completion {
                    case .finished:
                        print("🔍 DEBUG: Stream finished successfully")
                        // Save the completed assistant message
                        if let lastMessage = self?.messages.last, !lastMessage.isFromUser {
                            print("🔍 DEBUG: Saving final message: '\(lastMessage.content.suffix(50))...'")
                            self?.saveMessage(lastMessage)
                        }
                        HapticFeedback.messageReceived()

                    case .failure(let error):
                        print("🔍 DEBUG: Stream failed: \(error)")
                        self?.currentError = error
                        // Remove the loading message on error
                        self?.messages.removeLast()
                        HapticFeedback.errorOccurred()
                    }
                },
                receiveValue: { [weak self] content in
                    print("🔍 DEBUG: ChatViewModel received: '\(content)'")
                    guard let self = self, let lastIndex = self.messages.lastIndex(where: { !$0.isFromUser }) else {
                        print("🔍 DEBUG: No assistant message to update")
                        return
                    }

                    print("🔍 DEBUG: Animating text at index \(lastIndex)")
                    // For smooth typing effect, simulate character-by-character display
                    self.animateText(content, at: lastIndex)
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

        do {
            try managedObjectContext.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }

    func clearError() {
        currentError = nil
    }

    private func animateText(_ newContent: String, at index: Int) {
        let lastMessage = messages[index]
        let baseContent = lastMessage.content  // Content before this chunk
        let characters = Array(newContent)

        // Add characters one by one with a small delay for typing effect
        for (i, _) in characters.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) {
                // Add characters progressively: base + partial new content
                let partialNewContent = String(characters[0...i])
                let updatedContent = baseContent + partialNewContent

                self.messages[index] = MessageViewModel(
                    id: lastMessage.id,
                    content: updatedContent,
                    isFromUser: false,
                    timestamp: lastMessage.timestamp
                )
            }
        }
    }

    deinit {
        cancellables.removeAll()
    }
}

struct MessageViewModel: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date

    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
    }

    static func == (lhs: MessageViewModel, rhs: MessageViewModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.content == rhs.content &&
               lhs.isFromUser == rhs.isFromUser &&
               lhs.timestamp == rhs.timestamp
    }
}