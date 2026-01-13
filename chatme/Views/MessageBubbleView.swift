import SwiftUI

struct MessageBubbleView: View {
    let message: MessageViewModel
    @State private var showingCopiedAlert = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromUser {
                Spacer(minLength: 50)

                VStack(alignment: .trailing, spacing: 4) {
                    messageBubble
                        .contextMenu {
                            contextMenuButtons
                        }

                    timestampView
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    messageBubble
                        .contextMenu {
                            contextMenuButtons
                        }

                    timestampView
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .alert("Copied to clipboard", isPresented: $showingCopiedAlert) {
            Button("OK") { }
        }
    }

    private var messageBubble: some View {
        Group {
            if message.content.isEmpty && !message.isFromUser {
                // Typing indicator - 保留淡灰背景
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.gray.opacity(0.6))
                            .frame(width: 8, height: 8)
                            .scaleEffect(typingAnimation ? 1.0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                value: typingAnimation
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .onAppear {
                    typingAnimation = true
                }
            } else {
                if message.isFromUser {
                    // User messages: plain text
                    Text(message.content)
                        .font(.messageFont)
                        .foregroundColor(textColor)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(messageBubbleColor)
                        .clipShape(messageBubbleShape)
                        .textSelection(.enabled)
                } else {
                    // Assistant messages: Smart markdown rendering with streaming support
                    // 全宽无气泡样式
                    SmartMarkdownRenderer(content: message.content)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var contextMenuButtons: some View {
        Group {
            Button {
                copyMessage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            if !message.isFromUser && !message.content.isEmpty {
                Button {
                    // Could add regenerate functionality here
                    HapticFeedback.lightImpact()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }

            Button(role: .destructive) {
                // Could add delete functionality here
                HapticFeedback.lightImpact()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var timestampView: some View {
        Text(message.timestamp, style: .time)
            .font(.timestampFont)
            .foregroundColor(.textSecondary)
            .opacity(0.7)
    }

    // MARK: - Computed Properties
    private var messageBubbleColor: Color {
        message.isFromUser ? .messageBubbleUser : .messageBubbleAssistant
    }

    private var textColor: Color {
        message.isFromUser ? .white : .textPrimary
    }

    private var messageBubbleShape: some Shape {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
    }

    @State private var typingAnimation = false

    // MARK: - Actions
    private func copyMessage() {
        UIPasteboard.general.string = message.content
        HapticFeedback.textCopied()
        showingCopiedAlert = true
    }
}