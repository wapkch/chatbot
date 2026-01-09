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