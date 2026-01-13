import SwiftUI
import Foundation

struct InlineTextRenderer: View {
    let text: String
    @State private var attributedText: AttributedString = AttributedString()

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
            .onAppear {
                parseInlineText()
            }
            .onChange(of: text) { oldValue, newValue in
                parseInlineText()
            }
    }

    private func parseInlineText() {
        Task {
            let renderer = InlineMarkdownProcessor()
            let processed = await renderer.process(text)

            await MainActor.run {
                attributedText = processed
            }
        }
    }
}

// MARK: - Inline Markdown Processor
actor InlineMarkdownProcessor {
    func process(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Process in order: links, bold, italic, inline code
        result = processLinks(result)
        result = processBold(result)
        result = processItalic(result)
        result = processInlineCode(result)

        return result
    }

    private func processLinks(_ text: AttributedString) -> AttributedString {
        var result = text
        let linkPattern = #/\[([^\]]+)\]\(([^)]+)\)/#
        let stringContent = String(result.characters)

        while let match = stringContent.firstMatch(of: linkPattern) {
            let linkText = String(match.1)
            let linkURL = String(match.2)

            if let url = URL(string: linkURL) {
                if let range = result.range(of: match.0) {
                    var linkAttributes = AttributeContainer()
                    linkAttributes.foregroundColor = MarkdownTheme.Colors.link
                    linkAttributes.link = url

                    result.replaceSubrange(range, with: AttributedString(linkText, attributes: linkAttributes))
                }
            }
        }

        return result
    }

    private func processBold(_ text: AttributedString) -> AttributedString {
        var result = text
        let boldPattern = #/\*\*([^*]+)\*\*/#
        let stringContent = String(result.characters)

        while let match = stringContent.firstMatch(of: boldPattern) {
            let boldText = String(match.1)

            if let range = result.range(of: match.0) {
                var boldAttributes = AttributeContainer()
                boldAttributes.font = Font.system(size: 16, weight: .bold, design: .default)

                result.replaceSubrange(range, with: AttributedString(boldText, attributes: boldAttributes))
            }
        }

        return result
    }

    private func processItalic(_ text: AttributedString) -> AttributedString {
        var result = text
        let italicPattern = #/\*([^*]+)\*/#
        let stringContent = String(result.characters)

        while let match = stringContent.firstMatch(of: italicPattern) {
            let italicText = String(match.1)

            if let range = result.range(of: match.0) {
                var italicAttributes = AttributeContainer()
                italicAttributes.font = Font.system(size: 16, weight: .regular, design: .default).italic()

                result.replaceSubrange(range, with: AttributedString(italicText, attributes: italicAttributes))
            }
        }

        return result
    }

    private func processInlineCode(_ text: AttributedString) -> AttributedString {
        var result = text
        let codePattern = #/`([^`]+)`/#
        let stringContent = String(result.characters)

        while let match = stringContent.firstMatch(of: codePattern) {
            let codeText = String(match.1)

            if let range = result.range(of: match.0) {
                var codeAttributes = AttributeContainer()
                codeAttributes.font = MarkdownTheme.Typography.inlineCodeFont
                codeAttributes.backgroundColor = MarkdownTheme.Colors.inlineCodeBackground
                codeAttributes.foregroundColor = MarkdownTheme.Colors.primaryText

                result.replaceSubrange(range, with: AttributedString(codeText, attributes: codeAttributes))
            }
        }

        return result
    }
}

// MARK: - String Extensions for Range Conversion
private extension AttributedString {
    func range(of substring: Substring) -> Range<AttributedString.Index>? {
        guard let stringRange = String(self.characters).range(of: String(substring)) else {
            return nil
        }

        let startIndex = self.index(self.startIndex, offsetByCharacters: String(self.characters).distance(from: String(self.characters).startIndex, to: stringRange.lowerBound))
        let endIndex = self.index(startIndex, offsetByCharacters: substring.count)

        return startIndex..<endIndex
    }
}
