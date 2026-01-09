//
//  ChatmeApp.swift
//  chatme
//
//  Created by wangchao on 2026/1/9.
//

import SwiftUI
import CoreData

/// Main app entry point for the Chatme application
@main
struct ChatmeApp: App {
    /// Shared persistence controller for Core Data management
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
