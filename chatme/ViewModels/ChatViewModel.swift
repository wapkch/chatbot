import Foundation
import Combine
import CoreData

class ChatViewModel: ObservableObject {
    @Published var messages: [MessageViewModel] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var currentError: APIError?
    @Published var currentConversation: Conversation?

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

        openAIService.sendMessage(userMessage, configuration: configuration, conversationHistory: conversationHistory)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false

                    switch completion {
                    case .finished:
                        // Save the completed assistant message
                        if let lastMessage = self?.messages.last, !lastMessage.isFromUser {
                            self?.saveMessage(lastMessage)
                        }
                        HapticFeedback.messageReceived()

                    case .failure(let error):
                        self?.currentError = error
                        // Remove the loading message on error
                        self?.messages.removeLast()
                        HapticFeedback.errorOccurred()
                    }
                },
                receiveValue: { [weak self] content in
                    print("🔍 STREAMING: [\(Date())] Chunk received: '\(content)'")
                    guard let self = self, let lastIndex = self.messages.lastIndex(where: { !$0.isFromUser }) else {
                        return
                    }

                    // CRITICAL FIX: Do the update synchronously to avoid race conditions
                    let lastMessage = self.messages[lastIndex]
                    let updatedContent = lastMessage.content + content

                    print("🔍 STREAMING: Updating UI from '\(lastMessage.content)' to '\(updatedContent)'")

                    self.messages[lastIndex] = MessageViewModel(
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

        do {
            try managedObjectContext.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }

    func clearError() {
        currentError = nil
    }

    @MainActor
    func regenerateMessage(for messageToRegenerate: MessageViewModel) {
        guard !messageToRegenerate.isFromUser,
              let configuration = configurationManager.activeConfiguration,
              let messageIndex = messages.firstIndex(where: { $0.id == messageToRegenerate.id }) else {
            return
        }

        // 找到对应的用户消息（应该在AI消息之前）
        guard messageIndex > 0 else { return }
        let userMessageIndex = messageIndex - 1
        guard messages[userMessageIndex].isFromUser else { return }

        let userMessage = messages[userMessageIndex].content

        // 准备对话历史（只包含到要重新生成的消息之前的历史）
        let conversationHistory: [ChatMessage] = Array(messages.prefix(messageIndex)).compactMap { messageVM in
            // 只包含有内容的消息
            guard !messageVM.content.isEmpty else { return nil }
            return ChatMessage(role: messageVM.isFromUser ? .user : .assistant, content: messageVM.content)
        }

        // 删除当前的AI消息
        messages.remove(at: messageIndex)

        // 添加新的加载消息
        let loadingMessageVM = MessageViewModel(content: "", isFromUser: false, timestamp: Date())
        messages.insert(loadingMessageVM, at: messageIndex)

        isLoading = true
        currentError = nil

        openAIService.sendMessage(userMessage, configuration: configuration, conversationHistory: conversationHistory)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false

                    switch completion {
                    case .finished:
                        // 保存完成的助手消息
                        if let lastMessage = self?.messages.last, !lastMessage.isFromUser {
                            self?.saveMessage(lastMessage)
                        }
                        HapticFeedback.messageReceived()

                    case .failure(let error):
                        self?.currentError = error
                        // 错误时移除加载消息
                        self?.messages.removeLast()
                        HapticFeedback.errorOccurred()
                    }
                },
                receiveValue: { [weak self] content in
                    print("🔄 REGENERATING: [\(Date())] Chunk received: '\(content)'")
                    guard let self = self, let lastIndex = self.messages.lastIndex(where: { !$0.isFromUser }) else {
                        return
                    }

                    let lastMessage = self.messages[lastIndex]
                    let updatedContent = lastMessage.content + content

                    self.messages[lastIndex] = MessageViewModel(
                        id: lastMessage.id,
                        content: updatedContent,
                        isFromUser: false,
                        timestamp: lastMessage.timestamp
                    )
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Conversation Management

    /// 开始新会话
    func startNewConversation() {
        // 1. 保存当前会话（如果有消息）
        if !messages.isEmpty && currentConversation != nil {
            saveCurrentConversation()
        }

        // 2. 创建新会话
        let newConversation = conversationStore.createNewConversation()

        // 3. 重置状态
        messages.removeAll()
        currentConversation = newConversation
        isLoading = false
        currentError = nil
        inputText = ""
    }

    /// 切换到指定会话
    func switchToConversation(_ conversation: Conversation) {
        // 1. 保存当前会话
        if !messages.isEmpty && currentConversation != nil {
            saveCurrentConversation()
        }

        // 2. 加载选定会话的消息
        loadMessages(for: conversation)

        // 3. 更新当前会话
        currentConversation = conversation
    }

    /// 保存当前会话
    private func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }

        // 清除会话中的现有消息（避免重复）
        if let existingMessages = conversation.messages {
            for message in existingMessages {
                if let message = message as? Message {
                    managedObjectContext.delete(message)
                }
            }
        }

        // 保存当前消息到会话
        for messageViewModel in messages {
            let message = Message(context: managedObjectContext)
            message.id = messageViewModel.id
            message.content = messageViewModel.content
            message.isFromUser = messageViewModel.isFromUser
            message.timestamp = messageViewModel.timestamp
            message.conversation = conversation
        }

        // 更新会话信息
        conversation.updatedAt = Date()
        conversation.messageCount = Int32(messages.count)

        // 如果还没有标题或标题是默认的，生成标题
        if (conversation.title == nil || conversation.title == "新会话") && messages.count >= 2 {
            generateTitleIfNeeded(for: conversation)
        }

        do {
            try managedObjectContext.save()
        } catch {
            print("Failed to save current conversation: \(error)")
        }
    }

    /// 为指定会话生成标题
    private func generateTitleIfNeeded(for conversation: Conversation) {
        // 需要至少一轮用户消息和AI回复
        let userMessages = messages.filter { $0.isFromUser }
        let aiMessages = messages.filter { !$0.isFromUser }

        if let firstUserMessage = userMessages.first?.content,
           let firstAiMessage = aiMessages.first?.content {
            let generatedTitle = conversationStore.generateTitleForConversation(
                conversation,
                userMessage: firstUserMessage,
                aiResponse: firstAiMessage
            )
            conversation.title = generatedTitle
        }
    }

    /// 为特定会话加载消息
    private func loadMessages(for conversation: Conversation) {
        let request: NSFetchRequest<Message> = Message.fetchRequest()
        request.predicate = NSPredicate(format: "conversation == %@", conversation)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Message.timestamp, ascending: true)]

        do {
            let coreDataMessages = try managedObjectContext.fetch(request)
            messages = coreDataMessages.map { message in
                MessageViewModel(
                    id: message.id ?? UUID(),
                    content: message.content ?? "",
                    isFromUser: message.isFromUser,
                    timestamp: message.timestamp ?? Date()
                )
            }
        } catch {
            print("Failed to load messages for conversation: \(error)")
            messages = []
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