import SwiftUI
import CoreData

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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        chatViewModel.clearMessages()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
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