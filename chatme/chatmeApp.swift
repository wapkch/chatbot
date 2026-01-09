//
//  chatmeApp.swift
//  chatme
//
//  Created by wangchao on 2026/1/9.
//

import SwiftUI
import CoreData

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
