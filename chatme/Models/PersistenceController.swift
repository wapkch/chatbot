//
//  PersistenceController.swift
//  chatme
//
//  Created by wangchao on 2026/1/9.
//

import CoreData
import os.log

/// Controller responsible for managing Core Data persistence stack
/// Provides configurations for production, preview, and testing environments
class PersistenceController {
    /// Shared instance for production use
    static let shared = PersistenceController()

    /// Preview instance for SwiftUI previews with sample data
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)

        // Add sample data for previews
        let viewContext = controller.container.viewContext

        // Create sample conversation
        let sampleConversation = Conversation(context: viewContext)
        sampleConversation.id = UUID()
        sampleConversation.title = "Sample Conversation"
        sampleConversation.createdAt = Date()
        sampleConversation.updatedAt = Date()
        sampleConversation.messageCount = 2

        // Create sample messages
        let message1 = Message(context: viewContext)
        message1.id = UUID()
        message1.content = "Hello, how are you?"
        message1.isFromUser = true
        message1.timestamp = Date().addingTimeInterval(-3600)
        message1.conversation = sampleConversation

        let message2 = Message(context: viewContext)
        message2.id = UUID()
        message2.content = "I'm doing great, thanks for asking!"
        message2.isFromUser = false
        message2.timestamp = Date()
        message2.conversation = sampleConversation

        do {
            try viewContext.save()
        } catch {
            // For previews, we can use fatalError as it's not production code
            fatalError("Failed to create preview data: \(error)")
        }

        return controller
    }()

    /// Testing instance with in-memory store
    static let testing = PersistenceController(inMemory: true)

    let container: NSPersistentContainer
    private let logger = Logger(subsystem: "com.chatme.app", category: "PersistenceController")

    /// Initialize the persistence controller
    /// - Parameter inMemory: Whether to use in-memory store (for testing/preview)
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "DataModel")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Configure store settings for better performance and error handling
        container.persistentStoreDescriptions.forEach { storeDescription in
            storeDescription.shouldMigrateStoreAutomatically = true
            storeDescription.shouldInferMappingModelAutomatically = true
        }

        var loadError: Error?
        let group = DispatchGroup()
        group.enter()

        container.loadPersistentStores { _, error in
            loadError = error
            group.leave()
        }

        group.wait()

        if let error = loadError {
            logger.error("Core Data failed to load: \(error.localizedDescription)")

            // Try to recover by removing the store and recreating it
            if !inMemory {
                handleStoreLoadFailure(error: error)
            } else {
                // For in-memory stores, we can't recover, so throw the error
                fatalError("Failed to create in-memory store: \(error)")
            }
        }

        // Configure context for better performance
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Handle store loading failures by attempting recovery
    private func handleStoreLoadFailure(error: Error) {
        logger.warning("Attempting to recover from store load failure")

        guard let storeURL = container.persistentStoreDescriptions.first?.url else {
            fatalError("Could not determine store URL for recovery")
        }

        do {
            // Remove corrupted store files
            let fileManager = FileManager.default
            try fileManager.removeItem(at: storeURL)

            // Remove associated files
            let storeDirectory = storeURL.deletingLastPathComponent()
            let storeName = storeURL.deletingPathExtension().lastPathComponent

            let associatedFiles = [
                "\(storeName)-wal",
                "\(storeName)-shm"
            ]

            for fileName in associatedFiles {
                let fileURL = storeDirectory.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                }
            }

            // Attempt to reload the store
            var reloadError: Error?
            let group = DispatchGroup()
            group.enter()

            container.loadPersistentStores { _, error in
                reloadError = error
                group.leave()
            }

            group.wait()

            if let reloadError = reloadError {
                logger.error("Failed to recover store: \(reloadError.localizedDescription)")
                fatalError("Could not recover from Core Data failure: \(reloadError)")
            }

            logger.info("Successfully recovered from store corruption")

        } catch {
            logger.error("Failed to remove corrupted store: \(error.localizedDescription)")
            fatalError("Could not recover from Core Data failure: \(error)")
        }
    }

    /// Save the current context with proper error handling
    /// - Throws: CoreDataError if save operation fails
    func save() throws {
        let context = container.viewContext

        guard context.hasChanges else {
            return // No changes to save
        }

        do {
            try context.save()
            logger.debug("Context saved successfully")
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription)")

            // Rollback changes to maintain consistency
            context.rollback()

            throw CoreDataError.saveFailed(error)
        }
    }

    /// Save the current context without throwing errors (for legacy compatibility)
    /// - Returns: Bool indicating whether the save was successful
    @discardableResult
    func saveIfPossible() -> Bool {
        do {
            try save()
            return true
        } catch {
            logger.error("Save operation failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// Errors that can occur during Core Data operations
enum CoreDataError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case deleteFailed(Error)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete data: \(error.localizedDescription)"
        }
    }
}