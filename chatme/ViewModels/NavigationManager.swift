//
//  NavigationManager.swift
//  chatme
//
//  Created by Claude on 2026/1/12.
//

import SwiftUI
import Combine

@MainActor
class NavigationManager: ObservableObject {
    @Published var isSidebarOpen: Bool = false
    @Published var currentConversation: Conversation?
    @Published var searchText: String = ""

    // 会话分组数据
    @Published var conversationGroups: [ConversationGroup] = []

    private let conversationStore: ConversationStore
    private var cancellables = Set<AnyCancellable>()

    init(conversationStore: ConversationStore) {
        self.conversationStore = conversationStore
        setupBindings()
        refreshConversationList()
    }

    // MARK: - Public Methods

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSidebarOpen.toggle()
        }
    }

    func closeSidebar() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isSidebarOpen = false
        }
    }

    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
        closeSidebar()
    }

    func startNewConversation() {
        // 这个方法会在 ChatViewModel 中实现具体逻辑
        // NavigationManager 只负责状态管理
        closeSidebar()
    }

    func refreshConversationList() {
        Task {
            let groups = await conversationStore.getConversationsGroupedByDate()
            await MainActor.run {
                self.conversationGroups = groups
            }
        }
    }

    func deleteConversation(_ conversation: Conversation) {
        conversationStore.deleteConversation(conversation)
        refreshConversationList()

        // 如果删除的是当前会话，清空当前会话
        if currentConversation?.id == conversation.id {
            currentConversation = nil
        }
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // 监听搜索文本变化
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] searchText in
                self?.performSearch(searchText)
            }
            .store(in: &cancellables)
    }

    private func performSearch(_ query: String) {
        Task {
            let groups: [ConversationGroup]
            if query.isEmpty {
                groups = await conversationStore.getConversationsGroupedByDate()
            } else {
                let searchResults = await conversationStore.searchConversations(query: query)
                // 将搜索结果包装成一个组
                groups = searchResults.isEmpty ? [] : [ConversationGroup(title: "搜索结果", conversations: searchResults)]
            }

            await MainActor.run {
                self.conversationGroups = groups
            }
        }
    }
}

// MARK: - ConversationGroup Model

struct ConversationGroup: Identifiable {
    let id = UUID()
    let title: String
    let conversations: [Conversation]
}