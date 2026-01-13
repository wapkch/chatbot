import SwiftUI
import Foundation

struct AdvancedMarkdownRenderer: View {
    let content: String
    let isStreaming: Bool

    @State private var parsedElements: [MarkdownElement] = []
    @State private var parseTask: Task<Void, Never>?

    init(content: String, isStreaming: Bool = false) {
        self.content = content
        self.isStreaming = isStreaming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parsedElements, id: \.id) { element in
                renderElement(element)
            }
        }
        .onAppear {
            parseContent()
        }
        .onChange(of: content) { oldValue, newValue in
            parseContent()
        }
    }

    private func parseContent() {
        parseTask?.cancel()

        parseTask = Task {
            let parser = MarkdownParser()
            let elements = await parser.parseStreaming(content, isComplete: !isStreaming)

            await MainActor.run {
                if !Task.isCancelled {
                    parsedElements = elements
                }
            }
        }
    }

    @ViewBuilder
    private func renderElement(_ element: MarkdownElement) -> some View {
        switch element.type {
        case .heading(let level):
            HeadingView(text: element.content, level: level)
        case .paragraph:
            ParagraphView(content: element.content)
        case .codeBlock(let language):
            CodeBlockView(code: element.content, language: language, isStreaming: isStreaming)
                .padding(.vertical, MarkdownTheme.Spacing.paragraphGap / 2)
        case .list(let ordered):
            ListView(items: element.children ?? [], ordered: ordered)
        case .blockquote:
            BlockquoteView(content: element.content)
        case .horizontalRule:
            DividerView()
        }
    }
}

// MARK: - Markdown Element Model
struct MarkdownElement {
    let id = UUID()
    let type: MarkdownElementType
    let content: String
    let children: [MarkdownElement]?

    init(type: MarkdownElementType, content: String, children: [MarkdownElement]? = nil) {
        self.type = type
        self.content = content
        self.children = children
    }
}

enum MarkdownElementType {
    case heading(level: Int)
    case paragraph
    case codeBlock(language: String?)
    case list(ordered: Bool)
    case blockquote
    case horizontalRule
}

// MARK: - Heading View
struct HeadingView: View {
    let text: String
    let level: Int

    var body: some View {
        InlineTextRenderer(text: text)
            .font(headingFont)
            .fontWeight(.bold)
            .foregroundColor(MarkdownTheme.Colors.primaryText)
            .lineSpacing(MarkdownTheme.Typography.headingLineSpacing)
            .padding(.top, headingTopPadding)
            .padding(.bottom, MarkdownTheme.Spacing.headingBottom)
    }

    private var headingFont: Font {
        switch level {
        case 1: return MarkdownTheme.Typography.h1Font
        case 2: return MarkdownTheme.Typography.h2Font
        case 3: return MarkdownTheme.Typography.h3Font
        default: return MarkdownTheme.Typography.h3Font
        }
    }

    private var headingTopPadding: CGFloat {
        switch level {
        case 1: return MarkdownTheme.Spacing.headingTopH1
        case 2: return MarkdownTheme.Spacing.headingTopH2
        default: return MarkdownTheme.Spacing.headingTopH3
        }
    }
}

// MARK: - Paragraph View
struct ParagraphView: View {
    let content: String

    var body: some View {
        InlineTextRenderer(text: content)
            .font(MarkdownTheme.Typography.bodyFont)
            .foregroundColor(MarkdownTheme.Colors.primaryText)
            .lineSpacing(MarkdownTheme.Typography.bodyLineSpacing)
            .padding(.vertical, MarkdownTheme.Spacing.paragraphGap / 2)
    }
}

// MARK: - Blockquote View
struct BlockquoteView: View {
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(MarkdownTheme.Colors.blockquoteBorder)
                .frame(width: MarkdownTheme.Spacing.blockquoteBorderWidth)

            InlineTextRenderer(text: content)
                .font(MarkdownTheme.Typography.bodyFont)
                .foregroundColor(MarkdownTheme.Colors.secondaryText)
                .lineSpacing(MarkdownTheme.Typography.bodyLineSpacing)
                .padding(.leading, MarkdownTheme.Spacing.blockquoteIndent)
        }
        .padding(.vertical, MarkdownTheme.Spacing.paragraphGap / 2)
    }
}

// MARK: - List View
struct ListView: View {
    let items: [MarkdownElement]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: MarkdownTheme.Spacing.listItemGap) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(MarkdownTheme.Typography.bodyFont)
                        .foregroundColor(MarkdownTheme.Colors.secondaryText)
                        .frame(minWidth: 20, alignment: .leading)

                    InlineTextRenderer(text: item.content)
                        .font(MarkdownTheme.Typography.bodyFont)
                        .foregroundColor(MarkdownTheme.Colors.primaryText)
                        .lineSpacing(MarkdownTheme.Typography.bodyLineSpacing)
                }
            }
        }
        .padding(.leading, MarkdownTheme.Spacing.listIndent)
        .padding(.vertical, MarkdownTheme.Spacing.paragraphGap / 2)
    }
}

// MARK: - Divider View
struct DividerView: View {
    var body: some View {
        Rectangle()
            .fill(MarkdownTheme.Colors.divider)
            .frame(height: 1)
            .padding(.vertical, MarkdownTheme.Spacing.dividerVerticalPadding)
    }
}

// MARK: - String Extension for Regex Matches
private extension String {
    func countMatches(of regex: Regex<Substring>) async -> Int {
        var count = 0
        var start = self.startIndex

        while start < self.endIndex {
            if let match = self[start...].firstMatch(of: regex) {
                count += 1
                start = match.range.upperBound
            } else {
                break
            }
        }

        return count
    }

    func matches(of regex: Regex<Substring>) -> [Regex<Substring>.Match] {
        var matches: [Regex<Substring>.Match] = []
        var start = self.startIndex

        while start < self.endIndex {
            if let match = self[start...].firstMatch(of: regex) {
                matches.append(match)
                start = match.range.upperBound
            } else {
                break
            }
        }

        return matches
    }
}
