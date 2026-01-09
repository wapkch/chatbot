import SwiftUI
import CoreData

struct SettingsView: View {
    let configurationManager: ConfigurationManager
    let conversationStore: ConversationStore
    @Environment(\.presentationMode) var presentationMode

    // UI State
    @State private var showingConfigurations = false
    @State private var showingClearChatAlert = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                // API Configuration Section
                Section(header: Text("API Configuration")) {
                    NavigationLink(
                        destination: ConfigurationListView(configurationManager: configurationManager),
                        isActive: $showingConfigurations
                    ) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("Manage Configurations")
                                    .font(.body)
                                if let activeConfig = configurationManager.activeConfiguration {
                                    Text("Active: \(activeConfig.name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("No active configuration")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }

                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("Configuration Status")
                                .font(.body)
                            Text("\(configurationManager.configurations.count) configuration(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Chat Management Section
                Section(header: Text("Chat Management")) {
                    Button(action: {
                        HapticFeedback.lightImpact()
                        showingClearChatAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("Clear All Conversations")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Delete all chat history")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    HStack {
                        Image(systemName: "message")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("Total Conversations")
                                .font(.body)
                            Text("\(conversationStore.conversations.count) conversation(s)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // About Section
                Section(header: Text("About")) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("ChatMe")
                                .font(.body)
                            Text("AI Chat Client")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "number.circle")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("Version")
                                .font(.body)
                            Text("1.0.0")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.green)
                            .frame(width: 24)
                        VStack(alignment: .leading) {
                            Text("Privacy & Security")
                                .font(.body)
                            Text("API keys stored securely in Keychain")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Error Display Section
                if let lastError = configurationManager.lastError {
                    Section(header: Text("Configuration Error")) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("Last Error")
                                    .font(.body)
                                Text(lastError.localizedDescription)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Button("Clear Error") {
                            HapticFeedback.lightImpact()
                            configurationManager.clearError()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }

                // Debug Section (hidden in production)
                #if DEBUG
                Section(header: Text("Debug")) {
                    Button("Reload Configurations") {
                        HapticFeedback.lightImpact()
                        Task {
                            await configurationManager.loadConfigurations()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                #endif
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticFeedback.lightImpact()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert("Clear All Conversations", isPresented: $showingClearChatAlert) {
                Button("Clear All", role: .destructive) {
                    HapticFeedback.warning()
                    clearAllConversations()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all conversations and messages. This action cannot be undone.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func clearAllConversations() {
        conversationStore.clearAllConversations()
    }
}

// MARK: - Preview
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        let configManager = ConfigurationManager()
        let conversationStore = ConversationStore(context: PersistenceController.preview.container.viewContext)

        SettingsView(
            configurationManager: configManager,
            conversationStore: conversationStore
        )
    }
}