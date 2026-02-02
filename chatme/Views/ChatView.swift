import SwiftUI
import CoreData

struct ChatView: View {
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var configurationManager = ConfigurationManager()
    @StateObject private var navigationManager: NavigationManager
    @Environment(\.managedObjectContext) private var viewContext
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var showingImagePicker = false
    @FocusState private var isInputFocused: Bool

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
                                    .padding(.top, 20)

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

                                Button(action: {
                                    showingSettings = true
                                    navigationManager.closeSidebar()
                                    HapticFeedback.lightImpact()
                                }) {
                                    HStack {
                                        Image(systemName: "gear")
                                            .font(.footnote)
                                        Text("Settings")
                                            .font(.footnote)
                                    }
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .padding(.bottom, 30)
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
                            MessageBubbleView(message: message, chatViewModel: chatViewModel)
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
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerSheet(
                selectedImages: .init(
                    get: { [] },
                    set: { images in
                        Task {
                            await handleSelectedImages(images)
                        }
                    }
                ),
                isPresented: $showingImagePicker,
                maxSelection: ImageCompressionConfig.maxImageCount
            )
        }
    }


    // MARK: - Input Area View
    private var inputAreaView: some View {
        VStack(spacing: 8) {
            // Image preview (when images are selected)
            if !chatViewModel.pendingImageAttachments.isEmpty {
                HStack {
                    ForEach(chatViewModel.pendingImageAttachments) { attachment in
                        ZStack(alignment: .topTrailing) {
                            AsyncThumbnailForInput(attachment: attachment)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            Button(action: {
                                chatViewModel.removeImageAttachment(attachment)
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .offset(x: 6, y: -6)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // Input row with + button, text field, and send button
            HStack(alignment: .center, spacing: 8) {
                // + button
                Button(action: {
                    showingImagePicker = true
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 36, height: 36)
                }
                .disabled(chatViewModel.isLoading)

                // Text field with background
                HStack {
                    TextField("Ask anything", text: $chatViewModel.inputText, axis: .vertical)
                        .font(.body)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .disabled(chatViewModel.isLoading)
                        .lineLimit(1...6)
                        .onSubmit {
                            if !chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                sendMessage()
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                // Send button
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: chatViewModel.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(shouldDisableSendButton ? .gray : .white)
                        .frame(width: 32, height: 32)
                        .background(shouldDisableSendButton ? Color(.systemGray5) : Color.black)
                        .clipShape(Circle())
                }
                .disabled(shouldDisableSendButton)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
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
        let hasText = !chatViewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImages = !chatViewModel.pendingImageAttachments.isEmpty
        return !(hasText || hasImages) && !chatViewModel.isLoading
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

        // 自动弹出键盘
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isInputFocused = true
        }
    }

    private func handleSelectedImages(_ images: [UIImage]) async {
        for image in images {
            do {
                let attachment = try await ImageStorageService.shared.saveImage(image)
                await MainActor.run {
                    chatViewModel.addImageAttachment(attachment)
                }
            } catch {
                print("Failed to save image: \(error)")
                // Handle error - perhaps show an alert
            }
        }
    }

}

// MARK: - AsyncThumbnailForInput

struct AsyncThumbnailForInput: View {
    let attachment: ImageAttachment

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(ProgressView().scaleEffect(0.8))
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    )
            }
        }
        .task {
            do {
                let loadedImage = try await ImageStorageService.shared.loadThumbnail(for: attachment)
                image = loadedImage
                isLoading = false
            } catch {
                print("Failed to load thumbnail: \(error)")
                isLoading = false
            }
        }
    }
}