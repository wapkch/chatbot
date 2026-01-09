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
                        LazyVStack(spacing: 12) {
                            ForEach(chatViewModel.messages) { message in
                                MessageBubbleView(message: message)
                                    .id(message.id)
                            }

                            // Add some bottom padding for better scrolling
                            Color.clear.frame(height: 20)
                        }
                        .padding(.top)
                    }
                    .background(Color.chatBackground)
                    .onChange(of: chatViewModel.messages.count) { _ in
                        if let lastMessage = chatViewModel.messages.last {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    // Also respond to message content changes (for streaming)
                    .onChange(of: chatViewModel.messages.last?.content ?? "") { _ in
                        if let lastMessage = chatViewModel.messages.last {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: chatViewModel.isLoading) { _ in
                        // Scroll when loading state changes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastMessage = chatViewModel.messages.last {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onTapGesture {
                        hideKeyboard()
                    }
                }

                Divider()
                    .background(Color(.separator))

                // Input area
                inputAreaView
            }
            .keyboardAware()
            .navigationTitle(configurationManager.activeConfiguration?.modelID ?? "ChatMe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") {
                        chatViewModel.clearMessages()
                        HapticFeedback.lightImpact()
                    }
                    .disabled(chatViewModel.messages.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                        HapticFeedback.lightImpact()
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
            SettingsView(
                configurationManager: configurationManager,
                conversationStore: chatViewModel.conversationStore
            )
        }
    }

    // MARK: - Input Area View
    private var inputAreaView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                TextField("Type a message...", text: $chatViewModel.inputText, axis: .vertical)
                    .font(.inputFont)
                    .textFieldStyle(.plain)
                    .disabled(chatViewModel.isLoading)
                    .lineLimit(1...6)
                    .onSubmit {
                        if !chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            sendMessage()
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            // Send button
            Button {
                sendMessage()
            } label: {
                Image(systemName: chatViewModel.isLoading ? "stop.circle.fill" : "paperplane.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(sendButtonColor)
                    .frame(width: 40, height: 40)
                    .background(sendButtonBackgroundColor)
                    .clipShape(Circle())
                    .loadingAnimation(chatViewModel.isLoading)
            }
            .disabled(shouldDisableSendButton)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.chatBackground)
    }

    // MARK: - Computed Properties
    private var sendButtonColor: Color {
        if chatViewModel.isLoading {
            return .red
        }
        return shouldDisableSendButton ? .gray : .white
    }

    private var sendButtonBackgroundColor: Color {
        if chatViewModel.isLoading {
            return .red.opacity(0.2)
        }
        return shouldDisableSendButton ? .gray.opacity(0.3) : .blue
    }

    private var shouldDisableSendButton: Bool {
        return chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !chatViewModel.isLoading
    }

    // MARK: - Methods
    private func sendMessage() {
        if chatViewModel.isLoading {
            // Stop current request
            // chatViewModel.stopCurrentRequest() // Implement if needed
            HapticFeedback.lightImpact()
        } else {
            HapticFeedback.messageSent()
            chatViewModel.sendMessage()
        }
    }

}