import SwiftUI

// Note: To enable syntax highlighting, add Highlightr package to your project:
// 1. In Xcode: File > Add Package Dependencies
// 2. Enter: https://github.com/raspu/Highlightr
// 3. Add to target: chatme
// Then uncomment the Highlightr import and related code below.

struct CodeBlockView: View {
    let code: String
    let language: String?
    let isStreaming: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isCopied = false

    init(code: String, language: String? = nil, isStreaming: Bool = false) {
        self.code = code
        self.language = language
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            headerBar

            // Code content
            codeContent
        }
        .clipShape(RoundedRectangle(cornerRadius: MarkdownTheme.CornerRadius.codeBlock))
        .overlay(
            RoundedRectangle(cornerRadius: MarkdownTheme.CornerRadius.codeBlock)
                .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            // Language label
            Text(displayLanguage)
                .font(MarkdownTheme.Typography.codeHeaderFont)
                .foregroundColor(MarkdownTheme.Colors.codeBlockHeaderText)

            Spacer()

            // Copy button (only show when not streaming)
            if !isStreaming {
                copyButton
            }
        }
        .padding(.horizontal, MarkdownTheme.Spacing.codeBlockHeaderPaddingH)
        .padding(.vertical, MarkdownTheme.Spacing.codeBlockHeaderPaddingV)
        .background(MarkdownTheme.Colors.codeBlockHeader)
    }

    private var displayLanguage: String {
        guard let lang = language?.lowercased(), !lang.isEmpty else {
            return "code"
        }
        return lang
    }

    // MARK: - Copy Button
    private var copyButton: some View {
        Button(action: copyCode) {
            HStack(spacing: 4) {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                Text(isCopied ? "Copied!" : "Copy")
                    .font(MarkdownTheme.Typography.codeHeaderFont)
            }
            .foregroundColor(isCopied ? MarkdownTheme.Colors.copyButtonSuccess : MarkdownTheme.Colors.codeBlockHeaderText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private func copyCode() {
        UIPasteboard.general.string = code
        isCopied = true

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }

    // MARK: - Code Content
    private var codeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(MarkdownTheme.Typography.codeFont)
                .foregroundColor(MarkdownTheme.Colors.codeText)
                .lineSpacing(MarkdownTheme.Typography.codeLineSpacing)
                .textSelection(.enabled)
                .padding(MarkdownTheme.Spacing.codeBlockPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MarkdownTheme.Colors.codeBlockBackground)
    }
}

// MARK: - Preview
#Preview("Code Block - Swift") {
    VStack(spacing: 20) {
        CodeBlockView(
            code: """
            func greet(name: String) {
                print("Hello, \\(name)!")
            }

            let message = greet(name: "World")
            """,
            language: "swift"
        )

        CodeBlockView(
            code: "const x = 42;",
            language: "javascript",
            isStreaming: true
        )
    }
    .padding()
}

#Preview("Code Block - Dark Mode") {
    VStack(spacing: 20) {
        CodeBlockView(
            code: """
            def hello():
                print("Hello, World!")
            """,
            language: "python"
        )
    }
    .padding()
    .preferredColorScheme(.dark)
}
