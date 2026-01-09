import SwiftUI
import Foundation

struct MarkdownText: View {
    let markdown: String
    @State private var attributedString: AttributedString = AttributedString()

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
        Task {
            do {
                // Use iOS 15+ native Markdown parsing
                let parsed = try AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                ))

                await MainActor.run {
                    attributedString = parsed
                }
            } catch {
                // Fallback to plain text if Markdown parsing fails
                await MainActor.run {
                    attributedString = AttributedString(markdown)
                }
                print("Markdown parsing failed: \(error)")
            }
        }
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