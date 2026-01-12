import Foundation
import CoreData
import Combine

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

        do {
            let coreDataConversations = try managedObjectContext.fetch(request)
            conversations = coreDataConversations.map { conversation in
                ConversationViewModel(
                    id: conversation.id ?? UUID(),
                    title: conversation.title ?? "New Chat",
                    createdAt: conversation.createdAt ?? Date(),
                    updatedAt: conversation.updatedAt ?? Date(),
                    messageCount: Int(conversation.messageCount)
                )
            }
        } catch {
            print("Failed to load conversations: \(error)")
            conversations = []
        }
    }

    func createConversation(title: String) -> ConversationViewModel? {
        let conversation = Conversation(context: managedObjectContext)
        conversation.id = UUID()
        conversation.title = title.isEmpty ? "New Chat" : title
        conversation.createdAt = Date()
        conversation.updatedAt = Date()
        conversation.messageCount = 0

        do {
            try managedObjectContext.save()
            let viewModel = ConversationViewModel(
                id: conversation.id!,
                title: conversation.title!,
                createdAt: conversation.createdAt!,
                updatedAt: conversation.updatedAt!,
                messageCount: Int(conversation.messageCount)
            )
            loadConversations() // Refresh the list
            return viewModel
        } catch {
            print("Failed to create conversation: \(error)")
            return nil
        }
    }

    func updateConversation(_ conversationViewModel: ConversationViewModel, title: String? = nil) {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", conversationViewModel.id as CVarArg)

        do {
            if let conversation = try managedObjectContext.fetch(request).first {
                if let title = title {
                    conversation.title = title
                }
                conversation.updatedAt = Date()

                try managedObjectContext.save()
                loadConversations()
            }
        } catch {
            print("Failed to update conversation: \(error)")
        }
    }

    func deleteConversation(_ conversationViewModel: ConversationViewModel) {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", conversationViewModel.id as CVarArg)

        do {
            if let conversation = try managedObjectContext.fetch(request).first {
                // Delete associated messages
                if let messages = conversation.messages {
                    for message in messages {
                        if let message = message as? Message {
                            managedObjectContext.delete(message)
                        }
                    }
                }

                managedObjectContext.delete(conversation)
                try managedObjectContext.save()
                loadConversations()
            }
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    func clearAllConversations() {
        let conversationRequest: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        let messageRequest: NSFetchRequest<Message> = Message.fetchRequest()

        do {
            // Delete all messages first
            let messages = try managedObjectContext.fetch(messageRequest)
            for message in messages {
                managedObjectContext.delete(message)
            }

            // Then delete all conversations
            let conversations = try managedObjectContext.fetch(conversationRequest)
            for conversation in conversations {
                managedObjectContext.delete(conversation)
            }

            try managedObjectContext.save()
            loadConversations()
        } catch {
            print("Failed to clear all conversations: \(error)")
        }
    }

    func updateMessageCount(for conversationId: UUID, count: Int) {
        let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", conversationId as CVarArg)

        do {
            if let conversation = try managedObjectContext.fetch(request).first {
                conversation.messageCount = Int32(count)
                conversation.updatedAt = Date()
                try managedObjectContext.save()
                loadConversations()
            }
        } catch {
            print("Failed to update message count: \(error)")
        }
    }

    // MARK: - New Methods for Enhanced Functionality

    /// 按日期分组获取会话列表（只显示有消息的会话）
    func getConversationsGroupedByDate() async -> [ConversationGroup] {
        return await withCheckedContinuation { continuation in
            managedObjectContext.perform {
                let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
                // 只获取有消息的会话
                request.predicate = NSPredicate(format: "messageCount > 0")
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.updatedAt, ascending: false)]

                do {
                    let coreDataConversations = try self.managedObjectContext.fetch(request)
                    let groupedConversations = self.groupConversationsByDate(coreDataConversations)
                    continuation.resume(returning: groupedConversations)
                } catch {
                    print("Failed to load conversations: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// 搜索会话（只搜索有消息的会话）
    func searchConversations(query: String) async -> [Conversation] {
        return await withCheckedContinuation { continuation in
            managedObjectContext.perform {
                let request: NSFetchRequest<Conversation> = Conversation.fetchRequest()
                // 搜索标题包含关键词且有消息的会话
                request.predicate = NSPredicate(format: "title CONTAINS[cd] %@ AND messageCount > 0", query)
                request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.updatedAt, ascending: false)]

                do {
                    let results = try self.managedObjectContext.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    print("Failed to search conversations: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// 创建新会话
    func createNewConversation() -> Conversation {
        let conversation = Conversation(context: managedObjectContext)
        conversation.id = UUID()
        conversation.title = "新会话"
        conversation.createdAt = Date()
        conversation.updatedAt = Date()
        conversation.messageCount = 0

        do {
            try managedObjectContext.save()
            loadConversations() // 刷新列表
            return conversation
        } catch {
            print("Failed to create new conversation: \(error)")
            // 返回一个临时的会话对象，不保存到数据库
            return conversation
        }
    }

    /// 切换到指定会话
    func switchToConversation(_ conversation: Conversation) {
        // 这个方法主要用于更新相关状态
        // 具体的切换逻辑会在 ChatViewModel 中实现
    }

    /// 删除会话 (接受 Conversation 对象)
    func deleteConversation(_ conversation: Conversation) {
        do {
            // 删除关联的消息
            if let messages = conversation.messages {
                for message in messages {
                    if let message = message as? Message {
                        managedObjectContext.delete(message)
                    }
                }
            }

            managedObjectContext.delete(conversation)
            try managedObjectContext.save()
            loadConversations()
        } catch {
            print("Failed to delete conversation: \(error)")
        }
    }

    /// 添加消息到会话
    func addMessage(_ messageContent: String, isFromUser: Bool, to conversation: Conversation) {
        let message = Message(context: managedObjectContext)
        message.id = UUID()
        message.content = messageContent
        message.isFromUser = isFromUser
        message.timestamp = Date()
        message.conversation = conversation

        conversation.updatedAt = Date()
        conversation.messageCount += 1

        do {
            try managedObjectContext.save()
        } catch {
            print("Failed to add message to conversation: \(error)")
        }
    }

    /// 智能生成会话标题
    func generateTitleForConversation(_ conversation: Conversation,
                                    userMessage: String,
                                    aiResponse: String) -> String {
        // 清理和预处理用户消息
        let cleanedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果是问题，保留关键词和问号
        if cleanedMessage.contains("?") || cleanedMessage.contains("？") {
            let keywords = extractKeywords(from: cleanedMessage)
            if !keywords.isEmpty {
                return keywords.prefix(3).joined(separator: " ") + "?"
            }
        }

        // 如果是请求或指令，提取动词和名词
        let actionKeywords = extractActionKeywords(from: cleanedMessage)
        if !actionKeywords.isEmpty {
            return actionKeywords.prefix(3).joined(separator: " ")
        }

        // 后备方案：使用消息前缀
        let maxLength = 20
        if cleanedMessage.count <= maxLength {
            return cleanedMessage
        } else {
            let endIndex = cleanedMessage.index(cleanedMessage.startIndex, offsetBy: maxLength)
            return String(cleanedMessage[..<endIndex]) + "..."
        }
    }

    // MARK: - Private Helper Methods

    private func groupConversationsByDate(_ conversations: [Conversation]) -> [ConversationGroup] {
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [Conversation]] = [:]

        for conversation in conversations {
            let updatedAt = conversation.updatedAt ?? Date()
            let groupTitle: String

            if calendar.isDateInToday(updatedAt) {
                groupTitle = "今天"
            } else if calendar.isDateInYesterday(updatedAt) {
                groupTitle = "昨天"
            } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(updatedAt) == true {
                groupTitle = "本周"
            } else {
                groupTitle = "更早"
            }

            if groups[groupTitle] == nil {
                groups[groupTitle] = []
            }
            groups[groupTitle]?.append(conversation)
        }

        // 按预定义顺序返回分组
        let orderedTitles = ["今天", "昨天", "本周", "更早"]
        return orderedTitles.compactMap { title in
            guard let conversations = groups[title], !conversations.isEmpty else { return nil }
            return ConversationGroup(title: title, conversations: conversations)
        }
    }

    private func extractKeywords(from text: String) -> [String] {
        // 简单的关键词提取逻辑
        let stopWords = ["的", "是", "在", "有", "和", "或", "但是", "如果", "请", "帮助", "我", "你", "他", "她", "它"]
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { word in
            !stopWords.contains(word) && word.count > 1
        }
    }

    private func extractActionKeywords(from text: String) -> [String] {
        // 提取动作相关的关键词
        let actionVerbs = ["写", "创建", "生成", "修改", "解释", "分析", "设计", "实现", "帮我", "帮助", "制作", "开发"]
        let words = text.components(separatedBy: .whitespacesAndNewlines)

        var keywords: [String] = []
        for (index, word) in words.enumerated() {
            if actionVerbs.contains(where: { word.contains($0) }) {
                keywords.append(word)
                // 添加动词后的名词
                if index + 1 < words.count {
                    keywords.append(words[index + 1])
                }
                break
            }
        }
        return keywords
    }
}

struct ConversationViewModel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messageCount: Int

    var formattedDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(updatedAt) {
            formatter.timeStyle = .short
            return formatter.string(from: updatedAt)
        } else if Calendar.current.isDateInYesterday(updatedAt) {
            return "Yesterday"
        } else {
            formatter.dateStyle = .medium
            return formatter.string(from: updatedAt)
        }
    }

    static func == (lhs: ConversationViewModel, rhs: ConversationViewModel) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.updatedAt == rhs.updatedAt &&
               lhs.messageCount == rhs.messageCount
    }
}