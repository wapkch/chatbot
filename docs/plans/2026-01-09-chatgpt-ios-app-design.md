# ChatGPT iOS App 设计文档

## 项目概述

一个支持 OpenAI 协议的简洁 iOS 聊天应用，模仿 ChatGPT 官方应用的界面风格，支持自定义 API 配置。

## 核心需求

1. 支持 OpenAI 协议的各种兼容服务
2. 自定义 baseURL、APIKey、ModelID 配置
3. 本地消息存储和搜索功能
4. 详细的错误诊断和调试功能
5. 仿 ChatGPT 官方应用的用户界面

## 技术架构

### 技术栈
- **UI 框架**: SwiftUI + Combine
- **数据存储**: Core Data (消息历史)
- **安全存储**: Keychain (API 密钥)
- **网络请求**: URLSession (支持流式响应)
- **架构模式**: MVVM + ObservableObject

### 核心组件

#### 1. 视图层 (Views)
- **ChatView**: 主聊天界面
- **SettingsView**: 配置管理界面
- **ConfigurationView**: API 配置编辑
- **ConversationHistoryView**: 历史对话浏览

#### 2. 视图模型层 (ViewModels)
- **ChatViewModel**: 管理当前对话状态
- **SettingsStore**: 管理应用设置和API配置
- **ConversationStore**: 管理历史对话数据

#### 3. 服务层 (Services)
- **APIService**: OpenAI 协议网络请求
- **ConfigurationManager**: 配置存储和管理
- **ConversationManager**: 对话数据持久化

#### 4. 数据模型 (Models)
- **Message**: 消息实体
- **Conversation**: 对话实体
- **APIConfiguration**: API 配置实体

## 数据流设计

### 消息发送流程
1. 用户输入消息 → ChatViewModel
2. 消息立即显示在UI并保存到本地
3. APIService 发送请求，开始流式接收
4. 实时更新AI响应内容
5. 完成后保存完整对话

### 状态管理
- **ChatViewModel**: 管理消息列表、输入状态、加载状态
- **ConversationStore**: 管理历史对话、搜索功能
- **SettingsStore**: 管理API配置、应用设置

## 错误处理系统

### 错误类型分类
```swift
enum APIError: Error, LocalizedError {
    case invalidURL(String)
    case authenticationFailed(String)
    case modelNotFound(String)
    case rateLimitExceeded(retryAfter: TimeInterval)
    case networkTimeout
    case invalidResponse(statusCode: Int, message: String)
}
```

### 错误处理层级
1. **网络层**: URL格式、连接超时、DNS解析
2. **认证层**: API Key验证、权限检查
3. **API层**: 模型验证、请求格式、服务器错误
4. **应用层**: 本地存储、配置管理

### 用户友好提示
- 提供具体错误原因和解决建议
- 支持一键跳转到相关设置页面
- 集成API配置测试工具
- 显示请求/响应日志用于调试

## 用户界面设计

### 主聊天界面 (ChatView)
- **导航栏**: 显示当前模型，设置按钮
- **消息区域**:
  - 用户消息：右侧对齐，蓝色气泡
  - AI消息：左侧对齐，灰色气泡
  - 支持长按复制消息
- **输入区域**: 底部固定文本框和发送按钮
- **加载状态**: 打字动画效果

### 设置界面 (SettingsView)
- **API配置组**:
  - 当前激活配置显示
  - 管理配置列表
- **对话管理组**:
  - 清空历史记录
  - 搜索历史对话
- **应用设置组**:
  - 主题切换
  - 字体大小调节
- **关于组**:
  - 版本信息
  - 反馈入口

### API配置管理
- **配置列表**: 显示所有保存的配置
- **编辑界面**: 表单式输入 baseURL、API Key、Model ID
- **预设模板**:
  - OpenAI 官方
  - Azure OpenAI
  - 自定义配置
- **测试功能**: 验证API配置有效性

### 历史对话管理
- **搜索功能**: 按消息内容搜索
- **对话列表**: 时间排序，显示预览
- **滑动操作**: 删除单个对话
- **批量管理**: 清空全部历史

## 数据存储设计

### Core Data 实体

#### Message 实体
- id: UUID (主键)
- content: String (消息内容)
- isFromUser: Bool (是否用户消息)
- timestamp: Date (时间戳)
- conversationID: UUID (所属对话ID)

#### Conversation 实体
- id: UUID (主键)
- title: String (对话标题，可从首条消息生成)
- createdAt: Date (创建时间)
- updatedAt: Date (最后更新时间)
- messageCount: Int (消息数量)

### Keychain 存储
- API 配置的敏感信息 (API Key)
- 配置以 JSON 格式加密存储

## API 集成设计

### OpenAI 协议支持
- 兼容标准 OpenAI Chat Completion API
- 支持流式响应 (Server-Sent Events)
- 自定义 baseURL 和请求头

### 配置管理
- 多配置文件支持
- 配置切换不需要重启应用
- 配置验证和测试功能

### 网络请求优化
- 请求超时处理
- 自动重试机制（指数退避）
- 网络状态监控

## 安全考虑

### 数据保护
- API Key 存储在 Keychain 中
- 本地消息数据加密
- 不在日志中记录敏感信息

### 网络安全
- 强制使用 HTTPS
- 证书验证
- 请求头安全设置

## 开发计划

### 第一阶段：核心功能
1. 基础 UI 框架搭建
2. API 服务集成
3. 基本聊天功能
4. 配置管理系统

### 第二阶段：完善功能
1. 历史对话管理
2. 搜索功能
3. 错误处理优化
4. UI 细节完善

### 第三阶段：优化提升
1. 性能优化
2. 用户体验改进
3. 测试覆盖
4. 文档完善

## 技术难点

1. **流式响应处理**: 需要正确解析 SSE 格式数据
2. **状态同步**: 多个 ViewModel 之间的数据一致性
3. **内存管理**: 长对话的消息列表内存优化
4. **配置安全**: API Key 的安全存储和传输

## 成功标准

1. 应用能够稳定连接各种 OpenAI 兼容服务
2. 界面流畅，用户体验接近官方 ChatGPT 应用
3. 错误处理完善，用户能够快速定位和解决配置问题
4. 消息历史可靠保存，搜索功能正常工作
5. 应用在各种网络环境下表现稳定