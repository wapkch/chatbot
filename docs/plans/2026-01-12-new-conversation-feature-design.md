# 新会话功能设计文档

## 概述

为 ChatMe iOS 应用添加类似 ChatGPT 的新会话功能，包括会话管理、侧边栏导航和智能标题生成。

## 功能需求

### 核心功能
- 右上角新会话按钮，点击后保存当前会话并创建新会话
- 左上角汉堡菜单，打开侧边栏显示历史会话列表
- 智能会话标题生成（基于首轮对话内容）
- 会话列表按日期分组显示
- 会话搜索功能
- 滑动删除会话功能

### 用户体验目标
- 参考 ChatGPT iOS 应用的交互模式
- 保持流畅的会话切换体验
- 确保数据安全，防止意外丢失对话内容

## 架构设计

### 数据层扩展

#### ConversationStore 功能增强
```swift
extension ConversationStore {
    // 智能标题生成
    func generateTitleForConversation(_ conversation: Conversation,
                                    userMessage: String,
                                    aiResponse: String) -> String

    // 按日期分组查询
    func getConversationsGroupedByDate() -> [ConversationGroup]

    // 搜索功能
    func searchConversations(query: String) -> [Conversation]

    // 会话切换管理
    func switchToConversation(_ conversation: Conversation)
    func createNewConversation() -> Conversation
}
```

#### 新增 ConversationGroup 模型
```swift
struct ConversationGroup: Identifiable {
    let id = UUID()
    let title: String        // "今天"、"昨天"、"本周"、"更早"
    let conversations: [Conversation]
}
```

### 状态管理层

#### NavigationManager
```swift
class NavigationManager: ObservableObject {
    @Published var isSidebarOpen: Bool = false
    @Published var currentConversation: Conversation?
    @Published var conversationGroups: [ConversationGroup] = []
    @Published var searchText: String = ""

    func toggleSidebar()
    func selectConversation(_ conversation: Conversation)
    func startNewConversation()
    func refreshConversationList()
}
```

## UI 组件设计

### 主界面结构
```swift
struct MainContentView: View {
    @StateObject private var navigationManager = NavigationManager()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 主聊天界面
                ChatView()
                    .offset(x: navigationManager.isSidebarOpen ? geometry.size.width * 0.75 : 0)
                    .disabled(navigationManager.isSidebarOpen)

                // 侧边栏
                if navigationManager.isSidebarOpen {
                    SidebarView()
                        .frame(width: geometry.size.width * 0.75)
                        .transition(.move(edge: .leading))
                }
            }
        }
    }
}
```

### 导航栏重设计
```swift
struct ChatNavigationBar: View {
    @Binding var showSidebar: Bool
    let onNewChat: () -> Void

    var body: some View {
        HStack {
            // 汉堡菜单按钮（左上角）
            Button(action: { showSidebar.toggle() }) {
                Image(systemName: "line.horizontal.3")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            Spacer()

            // 应用标题
            Text("ChatMe")
                .font(.headline)
                .fontWeight(.semibold)

            Spacer()

            // 新会话按钮（右上角）
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
```

### 侧边栏设计
```swift
struct SidebarView: View {
    @ObservedObject var navigationManager: NavigationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 头部
            HStack {
                Text("聊天记录")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("完成") { navigationManager.isSidebarOpen = false }
            }
            .padding()

            // 搜索框
            SearchBar(text: $navigationManager.searchText)
                .padding(.horizontal)

            // 分组会话列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(navigationManager.conversationGroups) { group in
                        ConversationGroupView(group: group,
                                            navigationManager: navigationManager)
                    }
                }
            }

            Spacer()

            // 设置按钮（底部隐藏位置）
            HStack {
                Spacer()
                Button("设置") {
                    // 打开设置页面
                }
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(
            // 点击外部关闭侧边栏
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    navigationManager.isSidebarOpen = false
                }
        )
    }
}
```

### 会话分组视图
```swift
struct ConversationGroupView: View {
    let group: ConversationGroup
    @ObservedObject var navigationManager: NavigationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 分组标题
            Text(group.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)

            // 会话列表
            ForEach(group.conversations) { conversation in
                ConversationRowView(conversation: conversation,
                                  isSelected: conversation.id == navigationManager.currentConversation?.id,
                                  navigationManager: navigationManager)
            }
        }
    }
}
```

### 会话行视图
```swift
struct ConversationRowView: View {
    let conversation: Conversation
    let isSelected: Bool
    @ObservedObject var navigationManager: NavigationManager

    var body: some View {
        Button(action: {
            navigationManager.selectConversation(conversation)
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title ?? "新会话")
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                navigationManager.deleteConversation(conversation)
            }
        }
    }
}
```

## 核心功能实现

### 智能标题生成算法

#### 基本策略
1. 提取用户第一条消息的关键信息
2. 结合 AI 回复的上下文
3. 生成15-30字符的简洁标题
4. 后备方案：使用消息前20个字符 + "..."

#### 实现示例
```swift
extension ConversationStore {
    func generateTitleForConversation(_ conversation: Conversation,
                                    userMessage: String,
                                    aiResponse: String) -> String {

        // 清理和预处理用户消息
        let cleanedMessage = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        // 如果是问题，保留关键词和问号
        if cleanedMessage.contains("?") || cleanedMessage.contains("？") {
            let keywords = extractKeywords(from: cleanedMessage)
            if !keywords.isEmpty {
                return keywords.joined(separator: " ") + "?"
            }
        }

        // 如果是请求或指令，提取动词和名词
        let actionKeywords = extractActionKeywords(from: cleanedMessage)
        if !actionKeywords.isEmpty {
            return actionKeywords.prefix(3).joined(separator: " ")
        }

        // 后备方案：使用消息前缀
        let maxLength = 20
        if cleanedMessage.count <= maxLength {
            return cleanedMessage
        } else {
            let endIndex = cleanedMessage.index(cleanedMessage.startIndex, offsetBy: maxLength)
            return String(cleanedMessage[..<endIndex]) + "..."
        }
    }

    private func extractKeywords(from text: String) -> [String] {
        // 简单的关键词提取逻辑
        // 移除常见停用词，保留核心概念
        let stopWords = ["的", "是", "在", "有", "和", "或", "但是", "如果", "请", "帮助"]
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        return words.filter { word in
            !stopWords.contains(word) && word.count > 1
        }
    }

    private func extractActionKeywords(from text: String) -> [String] {
        // 提取动作相关的关键词
        let actionVerbs = ["写", "创建", "生成", "修改", "解释", "分析", "设计", "实现"]
        let words = text.components(separatedBy: .whitespacesAndNewlines)

        var keywords: [String] = []
        for (index, word) in words.enumerated() {
            if actionVerbs.contains(word) {
                keywords.append(word)
                // 添加动词后的名词
                if index + 1 < words.count {
                    keywords.append(words[index + 1])
                }
                break
            }
        }
        return keywords
    }
}
```

### 会话切换逻辑

#### ChatViewModel 扩展
```swift
extension ChatViewModel {
    func startNewConversation() {
        // 1. 保存当前会话
        if !messages.isEmpty && currentConversation != nil {
            saveCurrentConversation()
        }

        // 2. 创建新会话
        let newConversation = conversationStore.createNewConversation()

        // 3. 重置状态
        messages.removeAll()
        currentConversation = newConversation
        isAwaitingResponse = false

        // 4. 通知导航管理器
        navigationManager.currentConversation = newConversation
        navigationManager.refreshConversationList()

        // 5. 关闭侧边栏（如果打开）
        navigationManager.isSidebarOpen = false
    }

    func switchToConversation(_ conversation: Conversation) {
        // 1. 保存当前会话
        if !messages.isEmpty && currentConversation != nil {
            saveCurrentConversation()
        }

        // 2. 加载选定会话的消息
        loadMessages(for: conversation)

        // 3. 更新当前会话
        currentConversation = conversation
        navigationManager.currentConversation = conversation

        // 4. 关闭侧边栏
        navigationManager.isSidebarOpen = false
    }

    private func saveCurrentConversation() {
        guard let conversation = currentConversation else { return }

        // 保存消息到 CoreData
        for message in messages {
            conversationStore.addMessage(message, to: conversation)
        }

        // 更新会话的最后更新时间
        conversation.updatedAt = Date()

        // 如果还没有标题且有足够的对话，生成标题
        if conversation.title == nil || conversation.title == "新会话" {
            generateTitleIfNeeded(for: conversation)
        }
    }

    private func generateTitleIfNeeded(for conversation: Conversation) {
        // 需要至少一轮用户消息和AI回复
        let userMessages = messages.filter { !$0.isFromUser }
        let aiMessages = messages.filter { $0.isFromUser }

        if let firstUserMessage = userMessages.first?.content,
           let firstAiMessage = aiMessages.first?.content {
            let generatedTitle = conversationStore.generateTitleForConversation(
                conversation,
                userMessage: firstUserMessage,
                aiResponse: firstAiMessage
            )
            conversation.title = generatedTitle
        }
    }
}
```

## 数据持久化

### CoreData 模型更新

#### Conversation 实体扩展
```swift
// 在现有的 Conversation 实体基础上确保包含以下属性：
// - id: UUID (主键)
// - title: String? (会话标题)
// - createdAt: Date (创建时间)
// - updatedAt: Date (最后更新时间)
// - messages: NSSet (关联的消息)

extension Conversation {
    var lastMessage: String? {
        guard let messages = messages?.allObjects as? [Message],
              let lastMessage = messages.sorted(by: { $0.timestamp < $1.timestamp }).last else {
            return nil
        }
        return lastMessage.content
    }

    var messageCount: Int {
        return messages?.count ?? 0
    }
}
```

## 性能优化

### 列表优化
- 使用 `LazyVStack` 处理大量历史会话
- 实现分页加载，每次加载50个会话
- 图片和复杂内容的延迟渲染

### 内存管理
- 及时释放未使用的会话消息
- 使用弱引用避免循环引用
- 合理的 CoreData 批处理大小

### 动画性能
- 使用 `@State` 和 `.animation()` 实现流畅的侧边栏动画
- 避免在动画期间进行重CPU计算
- 合理的动画时长和缓动曲线

## 测试策略

### 单元测试
- ConversationStore 的所有新增方法
- 标题生成算法的各种边界情况
- NavigationManager 的状态管理逻辑

### 集成测试
- 会话创建和切换的完整流程
- CoreData 并发访问的安全性
- 大量数据时的性能表现

### UI 测试
- 侧边栏的打开/关闭交互
- 会话列表的滚动和搜索
- 滑动删除功能

## 实现计划

### 阶段一：基础功能（第1-2周）
1. 重构导航栏，添加新会话按钮
2. 实现基础的新会话创建逻辑
3. 扩展 ConversationStore 的核心方法
4. 基础的会话切换功能

### 阶段二：界面和交互（第3-4周）
1. 实现侧边栏 UI 组件
2. 会话列表的分组显示
3. 搜索功能实现
4. 滑动删除功能

### 阶段三：优化和完善（第5-6周）
1. 智能标题生成算法优化
2. 性能优化和动画效果
3. 错误处理和边界情况
4. 全面测试和文档

## 风险评估

### 技术风险
- CoreData 并发操作的复杂性：**中等风险**
  - 缓解措施：使用 NSPersistentContainer 的标准并发模式

### 用户体验风险
- 大量历史会话的性能问题：**低风险**
  - 缓解措施：分页加载和虚拟化列表

### 数据安全风险
- 会话切换时数据丢失：**中等风险**
  - 缓解措施：实时保存和状态恢复机制

## 成功指标

### 功能指标
- 新会话创建成功率 > 99%
- 会话切换响应时间 < 300ms
- 侧边栏打开/关闭动画流畅度 60fps

### 用户体验指标
- 标题生成准确性 > 85%（主观评估）
- 搜索结果准确性 > 95%
- 用户操作错误率 < 2%

---

*此设计文档将作为开发的指导文件，在实现过程中可能会根据实际情况进行调整和优化。*