import SwiftUI
import Foundation

struct MarkdownText: View {
    let markdown: String
    @State private var attributedString: AttributedString = AttributedString()
    @State private var parseTask: Task<Void, Never>?

    var body: some View {
        Text(attributedString)
            .textSelection(.enabled)
            .onAppear {
                parseMarkdown()
            }
            .onChange(of: markdown) { _ in
                parseMarkdown()
            }
    }

    private func parseMarkdown() {
        // Cancel previous parsing task
        parseTask?.cancel()

        parseTask = Task {
            do {
                // For streaming content, only parse if content looks complete
                // This avoids constantly re-parsing incomplete markdown
                let shouldParseMarkdown = isContentComplete(markdown)

                let parsed: AttributedString
                if shouldParseMarkdown {
                    parsed = try AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(
                        interpretedSyntax: .inlineOnlyPreservingWhitespace
                    ))
                } else {
                    // For incomplete content, just show as plain text
                    parsed = AttributedString(markdown)
                }

                await MainActor.run {
                    if !Task.isCancelled {
                        attributedString = parsed
                    }
                }
            } catch {
                // Fallback to plain text if Markdown parsing fails
                await MainActor.run {
                    if !Task.isCancelled {
                        attributedString = AttributedString(markdown)
                    }
                }
            }
        }
    }

    private func isContentComplete(_ content: String) -> Bool {
        // Simple heuristic: consider content complete if it ends with punctuation or whitespace
        // This avoids parsing incomplete sentences during streaming
        return content.isEmpty || content.last?.isWhitespace == true || ".,!?;:".contains(content.last ?? " ")
    }
}

// MARK: - Preview
struct MarkdownText_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarkdownText(markdown: """
            # Heading 1

            This is **bold text** and *italic text*.

            ## Code Example

            Here's some `inline code` and a code block:

            ```swift
            func hello() {
                print("Hello, World!")
            }
            ```

            ## List

            - Item 1
            - Item 2
            - Item 3

            **Links:** [OpenAI](https://openai.com)
            """)
            .padding()

            Spacer()
        }
        .previewLayout(.sizeThatFits)
    }
}