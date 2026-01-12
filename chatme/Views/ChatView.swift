import SwiftUI
import CoreData

struct ChatView: View {
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var configurationManager = ConfigurationManager()
    @StateObject private var navigationManager: NavigationManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingSettings = false
    @State private var showingError = false

    init() {
        let configManager = ConfigurationManager()
        let context = PersistenceController.shared.container.viewContext
        let conversationStore = ConversationStore(context: context)

        let chatVM = ChatViewModel(
            configurationManager: configManager,
            context: context
        )

        let navManager = NavigationManager(conversationStore: conversationStore)

        _chatViewModel = StateObject(wrappedValue: chatVM)
        _configurationManager = StateObject(wrappedValue: configManager)
        _navigationManager = StateObject(wrappedValue: navManager)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 主聊天界面
                chatContentView
                    .offset(x: navigationManager.isSidebarOpen ? geometry.size.width * 0.75 : 0)
                    .disabled(navigationManager.isSidebarOpen)
                    .onTapGesture {
                        if navigationManager.isSidebarOpen {
                            navigationManager.closeSidebar()
                        }
                    }

                // 侧边栏 - 使用和调试版本相同的结构
                if navigationManager.isSidebarOpen {
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: geometry.size.width * 0.75)
                        .overlay(
                            VStack {
                                Text("Chat History")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .padding(.top, 100)

                                // 会话列表或占位符
                                if navigationManager.conversationGroups.isEmpty {
                                    Text("No conversations yet")
                                        .font(.body)
                                        .foregroundColor(.gray)
                                        .padding(.top, 50)
                                } else {
                                    ScrollView {
                                        LazyVStack(alignment: .leading, spacing: 0) {
                                            ForEach(navigationManager.conversationGroups) { group in
                                                // 分组标题
                                                HStack {
                                                    Text(group.title)
                                                        .font(.caption)
                                                        .fontWeight(.medium)
                                                        .foregroundColor(.gray)
                                                    Spacer()
                                                }
                                                .padding(.horizontal, 20)
                                                .padding(.top, 16)
                                                .padding(.bottom, 4)

                                                // 会话列表
                                                ForEach(group.conversations, id: \.id) { conversation in
                                                    ConversationRowView(
                                                        conversation: conversation,
                                                        isSelected: conversation.id == navigationManager.currentConversation?.id,
                                                        onTap: {
                                                            chatViewModel.switchToConversation(conversation)
                                                            navigationManager.selectConversation(conversation)
                                                        }
                                                    )
                                                }
                                            }
                                        }
                                        .padding(.top, 8)
                                    }
                                }

                                Spacer()

                                Button("Settings") {
                                    showingSettings = true
                                    navigationManager.closeSidebar()
                                    HapticFeedback.lightImpact()
                                }
                                .font(.footnote)
                                .foregroundColor(.gray)
                                .padding(.bottom, 50)
                            }
                        )
                        .transition(.move(edge: .leading))
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    // MARK: - Chat Content View
    private var chatContentView: some View {
        VStack(spacing: 0) {
            // 自定义导航栏
            ChatNavigationBar(
                title: configurationManager.activeConfiguration?.modelID ?? "ChatMe",
                onToggleSidebar: {
                    HapticFeedback.lightImpact()
                    navigationManager.toggleSidebar()
                    // 当侧边栏打开时刷新会话列表
                    if !navigationManager.isSidebarOpen {
                        navigationManager.refreshConversationList()
                    }
                },
                onNewChat: {
                    HapticFeedback.lightImpact()
                    startNewConversation()
                }
            )

            Divider()
                .background(Color(.separator))

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
        .background(Color.chatBackground)
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

    private func startNewConversation() {
        // 使用 ChatViewModel 的完整会话管理功能
        chatViewModel.startNewConversation()
        navigationManager.currentConversation = chatViewModel.currentConversation
        navigationManager.refreshConversationList()
        navigationManager.startNewConversation()
    }

}